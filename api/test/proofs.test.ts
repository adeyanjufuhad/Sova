import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import type { ProofStorage } from "../src/lib/storage.js";
import { DEMO_PIN, seedDemo } from "../src/seed/demo.js";
import { freshDatabase } from "./setup/db.js";

/** In-memory stand-in for the bucket: a key "exists" once the test uploads it. */
class FakeStorage implements ProofStorage {
  readonly uploaded = new Set<string>();
  async uploadUrl(key: string, contentType: string, size: number) {
    return `https://bucket.test/${key}?type=${encodeURIComponent(contentType)}&size=${size}`;
  }
  async viewUrl(key: string) {
    return `https://bucket.test/view/${key}`;
  }
  async exists(key: string) {
    return this.uploaded.has(key);
  }
}

const HALIMA = "+2348000000003"; // collects turn 3 of Office Esusu

let db: Awaited<ReturnType<typeof freshDatabase>>;
let storage: FakeStorage;
let ip = 0;
let office: string;
const tokens: Record<string, string> = {};

const config = () =>
  loadConfig({
    NODE_ENV: "test",
    LOG_LEVEL: "silent",
    JWT_SECRET: "test-secret-that-is-at-least-32-characters-long",
    DEMO_LOGIN_ENABLED: "true",
    OTP_TEST_NUMBERS: `${HALIMA}:123456`,
  });

async function call(app: FastifyInstance, who: string | null, method: "GET" | "POST", url: string, payload?: object) {
  const res = await app.inject({
    method,
    url,
    payload,
    remoteAddress: `10.3.0.${++ip}`,
    headers: who ? { authorization: `Bearer ${tokens[who]}` } : {},
  });
  return { status: res.statusCode, body: res.json() };
}

let app: FastifyInstance;

beforeAll(async () => {
  db = await freshDatabase();
  await seedDemo(db.pool);
  storage = new FakeStorage();
  app = await buildApp(config(), db.pool, { storage });
  tokens.ada = (await call(app, null, "POST", "/auth/demo")).body.accessToken;
  await call(app, null, "POST", "/auth/otp/request", { phone: HALIMA });
  tokens.halima = (await call(app, null, "POST", "/auth/otp/verify", { phone: HALIMA, code: "123456" })).body.accessToken;
  office = (await db.pool.query("select id from groups where invite_code = 'K7QX2M'")).rows[0].id;
});
afterAll(async () => db.drop());

describe("proof of payment photos", () => {
  it("accept only photos up to 5 MB", async () => {
    const pdf = await call(app, "ada", "POST", `/circles/${office}/rounds/3/proof`, { contentType: "application/pdf", size: 1000 });
    expect(pdf.status).toBe(400);
    const huge = await call(app, "ada", "POST", `/circles/${office}/rounds/3/proof`, { contentType: "image/jpeg", size: 6e6 });
    expect(huge.body.error.message).toMatch(/5 MB/);
  });

  it("upload straight to the bucket, then attach to the payment", async () => {
    const link = await call(app, "ada", "POST", `/circles/${office}/rounds/3/proof`, { contentType: "image/jpeg", size: 250_000 });
    expect(link.status).toBe(200);
    expect(link.body.key).toMatch(new RegExp(`^proofs/${office}/3/[0-9a-f-]{36}/[0-9a-f-]{36}[.]jpg$`));
    expect(link.body.uploadUrl).toContain("size=250000");

    // Not uploaded yet: refused.
    const early = await call(app, "ada", "POST", `/circles/${office}/rounds/3/pay`, { proofKey: link.body.key, pin: DEMO_PIN });
    expect(early.body.error.code).toBe("proof_missing");

    storage.uploaded.add(link.body.key);
    const paid = await call(app, "ada", "POST", `/circles/${office}/rounds/3/pay`, {
      bankReference: "FT2610ABC",
      proofKey: link.body.key,
      pin: DEMO_PIN,
    });
    expect(paid.status).toBe(200);
    const ada = paid.body.members.find((m: { name: string }) => m.name === "Ada Obi").id;
    const mine = paid.body.currentRound.contributions.find((c: { userId: string }) => c.userId === ada);
    expect(mine).toMatchObject({ status: "payer_confirmed", hasProof: true });

    // The collector sees it through a short-lived link; nobody outside the circle can.
    const view = await call(app, "halima", "GET", `/contributions/${mine.id}/proof`);
    expect(view.body.url).toBe(`https://bucket.test/view/${link.body.key}`);
    const church = (await db.pool.query("select id from groups where invite_code = 'CHRDA9'")).rows[0].id;
    const outsider = await call(app, "halima", "GET", `/circles/${church}`);
    expect(outsider.status).toBe(404);
  });

  it("refuse someone else's photo", async () => {
    const theirs = `proofs/${office}/3/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111.jpg`;
    storage.uploaded.add(theirs);
    const res = await call(app, "ada", "POST", `/circles/${office}/rounds/3/pay`, { proofKey: theirs, pin: DEMO_PIN });
    expect(res.body.error.code).toBe("proof_missing");
  });

  it("explain when uploads aren't set up", async () => {
    const bare = await buildApp(config(), db.pool, { storage: null });
    const res = await call(bare, "ada", "POST", `/circles/${office}/rounds/3/proof`, { contentType: "image/png", size: 1000 });
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe("uploads_not_configured");
  });
});
