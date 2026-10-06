import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import type { ProofStorage } from "../src/lib/storage.js";
import { DEMO_PIN, seedDemo } from "../src/seed/demo.js";
import { freshDatabase } from "./setup/db.js";

/** In-memory stand-in for the bucket. */
class FakeStorage implements ProofStorage {
  readonly objects = new Map<string, { body: Buffer; type: string }>();
  async put(key: string, body: Buffer, type: string) {
    this.objects.set(key, { body, type });
  }
  async viewUrl(key: string) {
    return `https://bucket.test/view/${key}`;
  }
  async exists(key: string) {
    return this.objects.has(key);
  }
}

const HALIMA = "+2348000000003"; // collects turn 3 of Office Esusu
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(200, 1)]);

let db: Awaited<ReturnType<typeof freshDatabase>>;
let storage: FakeStorage;
let app: FastifyInstance;
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

async function call(target: FastifyInstance, who: string | null, method: "GET" | "POST", url: string, payload?: object) {
  const res = await target.inject({
    method,
    url,
    payload,
    remoteAddress: `10.3.0.${++ip}`,
    headers: who ? { authorization: `Bearer ${tokens[who]}` } : {},
  });
  return { status: res.statusCode, body: res.json() };
}

async function upload(target: FastifyInstance, who: string, url: string, bytes: Buffer, contentType: string) {
  const res = await target.inject({
    method: "POST",
    url,
    payload: bytes,
    remoteAddress: `10.3.0.${++ip}`,
    headers: { authorization: `Bearer ${tokens[who]}`, "content-type": contentType },
  });
  return { status: res.statusCode, body: res.json() };
}

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
  it("accept only real images up to 5 MB, whatever the client claims", async () => {
    const url = `/circles/${office}/rounds/3/proof`;
    const disguised = await upload(app, "ada", url, Buffer.from("%PDF-1.7 not a photo"), "image/jpeg");
    expect(disguised.body.error.code).toBe("invalid_photo");
    const huge = await upload(app, "ada", url, Buffer.concat([JPEG, Buffer.alloc(5 * 1024 * 1024)]), "image/jpeg");
    expect(huge.status).toBe(413);
    const text = await upload(app, "ada", url, Buffer.from("hello"), "text/plain");
    expect(text.body.error.code).toBe("invalid_photo");
  });

  it("store the photo privately and attach it to the payment", async () => {
    const stored = await upload(app, "ada", `/circles/${office}/rounds/3/proof`, JPEG, "image/jpeg");
    expect(stored.status).toBe(200);
    expect(stored.body.key).toMatch(new RegExp(`^proofs/${office}/3/[0-9a-f-]{36}/[0-9a-f-]{36}[.]jpg$`));
    expect(storage.objects.get(stored.body.key)).toMatchObject({ type: "image/jpeg" });

    const paid = await call(app, "ada", "POST", `/circles/${office}/rounds/3/pay`, {
      bankReference: "FT2610ABC",
      proofKey: stored.body.key,
      pin: DEMO_PIN,
    });
    expect(paid.status).toBe(200);
    const ada = paid.body.members.find((m: { name: string }) => m.name === "Ada Obi").id;
    const mine = paid.body.currentRound.contributions.find((c: { userId: string }) => c.userId === ada);
    expect(mine).toMatchObject({ status: "payer_confirmed", hasProof: true });

    // The collector views it through a short-lived link.
    const view = await call(app, "halima", "GET", `/contributions/${mine.id}/proof`);
    expect(view.body.url).toBe(`https://bucket.test/view/${stored.body.key}`);
  });

  it("refuse photos that weren't uploaded, or belong to someone else", async () => {
    const missing = `proofs/${office}/3/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111.jpg`;
    const res = await call(app, "ada", "POST", `/circles/${office}/rounds/3/pay`, { proofKey: missing, pin: DEMO_PIN });
    expect(res.body.error.code).toBe("proof_missing");
    await storage.put(missing, JPEG, "image/jpeg");
    const theirs = await call(app, "ada", "POST", `/circles/${office}/rounds/3/pay`, { proofKey: missing, pin: DEMO_PIN });
    expect(theirs.body.error.code).toBe("proof_missing");
  });

  it("explain when uploads aren't set up", async () => {
    const bare = await buildApp(config(), db.pool, { storage: null });
    const res = await upload(bare, "ada", `/circles/${office}/rounds/3/proof`, JPEG, "image/jpeg");
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe("uploads_not_configured");
  });
});
