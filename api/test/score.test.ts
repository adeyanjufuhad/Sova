import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { scoreBand } from "../src/routes/score.js";
import { DEMO_PIN, seedDemo } from "../src/seed/demo.js";
import { freshDatabase } from "./setup/db.js";

const NEWCOMER = "+2348000000031";

let db: Awaited<ReturnType<typeof freshDatabase>>;
let app: FastifyInstance;
let ada: string;
let newcomer: string;

let ip = 0;
const nextIp = () => `10.3.${Math.floor(++ip / 250)}.${ip % 250}`;

async function call(token: string | null, method: "GET" | "POST" | "PATCH", url: string, payload?: object) {
  const res = await app.inject({
    method,
    url,
    payload,
    remoteAddress: nextIp(),
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
  return { status: res.statusCode, body: res.json(), raw: res.body };
}

beforeAll(async () => {
  db = await freshDatabase();
  await seedDemo(db.pool);
  app = await buildApp(
    loadConfig({
      NODE_ENV: "test",
      LOG_LEVEL: "silent",
      JWT_SECRET: "test-secret-that-is-at-least-32-characters-long",
      DEMO_LOGIN_ENABLED: "true",
      OTP_TEST_NUMBERS: `${NEWCOMER}:123456`,
    }),
    db.pool,
  );
  ada = (await call(null, "POST", "/auth/demo")).body.accessToken;

  await call(null, "POST", "/auth/otp/request", { phone: NEWCOMER });
  newcomer = (await call(null, "POST", "/auth/otp/verify", { phone: NEWCOMER, code: "123456" })).body.accessToken;
  await call(newcomer, "PATCH", "/me", { fullName: "Kelechi Nwankwo" });
  await call(newcomer, "POST", "/me/pin", { pin: "2580" });
});
afterAll(async () => db.drop());

describe("Sova Score", () => {
  it("labels scores in plain words", () => {
    expect([95, 90, 89, 75, 74, 50, 49, 0].map(scoreBand)).toEqual([
      "Excellent", "Excellent", "Strong", "Strong", "Fair", "Fair", "Building", "Building",
    ]);
  });

  it("shows a member with history their live score and how it's made up", async () => {
    const res = await call(ada, "GET", "/me/score");
    expect(res.status).toBe(200);
    const s = res.body;
    expect(s).toMatchObject({ ready: true, minimumPayments: 3, share: null });
    expect(s.confirmedPayments).toBeGreaterThanOrEqual(3);
    expect(s.onTimePayments).toBeLessThanOrEqual(s.confirmedPayments);
    expect(s.completedCircles).toBeGreaterThanOrEqual(1);
    // The v1 formula: 60% on time, 25% consistency, 15% completion.
    expect(s.score).toBe(Math.round(100 * (0.6 * s.onTimeRate + 0.25 * s.consistencyRate + 0.15 * s.completionRate)));
    expect(s.band).toBe(scoreBand(s.score));
  });

  it("doesn't count a turn that isn't due yet as a missed payment", async () => {
    // Ada still owes Office Esusu's turn 3, which is due in two days.
    const { rows } = await db.pool.query<{ due: string }>(
      `select r.due_date::text as due from rounds r join groups g on g.id = r.group_id
        where g.name = 'Office Esusu' and r.status = 'active'`,
    );
    expect(rows[0]!.due > new Date().toISOString().slice(0, 10)).toBe(true);
    const s = (await call(ada, "GET", "/me/score")).body;
    expect(s.consistencyRate).toBe(1);
  });

  it("waits for enough history before showing a newcomer a score", async () => {
    const s = (await call(newcomer, "GET", "/me/score")).body;
    expect(s).toMatchObject({ ready: false, score: null, band: null, confirmedPayments: 0 });
    const share = await call(newcomer, "POST", "/me/score/share", { pin: "2580" });
    expect(share.body.error.code).toBe("not_enough_history");
    expect(share.body.error.message).toContain("3 confirmed payments");
  });

  it("shares a snapshot behind a private link that shows no personal details", async () => {
    expect((await call(ada, "POST", "/me/score/share", { pin: "9999" })).body.error.code).toBe("wrong_pin");
    await db.pool.query("select reset_pin_attempts(id) from users where phone = '+2348000000000'");

    const shared = await call(ada, "POST", "/me/score/share", { pin: DEMO_PIN });
    expect(shared.status).toBe(201);
    const token = shared.body.share.token as string;
    expect(token).toMatch(/^[A-Za-z0-9_-]{22,64}$/);

    const card = await call(null, "GET", `/public/scores/${token}`);
    expect(card.status).toBe(200);
    expect(card.body).toMatchObject({ displayName: "Ada O.", score: shared.body.score, band: shared.body.band });
    expect(card.body.token).toBeUndefined();
    expect(card.raw).not.toMatch(/\+234|\b\d{10,11}\b|Esusu|Ajo|Adashe|₦/);
  });

  it("replaces the old link when sharing again, and stops on request", async () => {
    const first = (await call(ada, "GET", "/me/score")).body.share.token;
    const again = (await call(ada, "POST", "/me/score/share", { pin: DEMO_PIN })).body.share.token;
    expect(again).not.toBe(first);
    expect((await call(null, "GET", `/public/scores/${first}`)).status).toBe(404);
    expect((await call(null, "GET", `/public/scores/${again}`)).status).toBe(200);

    const stopped = await call(ada, "POST", "/me/score/share/stop");
    expect(stopped.body.share).toBeNull();
    expect((await call(null, "GET", `/public/scores/${again}`)).status).toBe(404);
    expect((await call(null, "GET", "/public/scores/not-a-token")).status).toBe(400);
  });
});
