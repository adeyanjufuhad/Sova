import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { freshDatabase } from "./setup/db.js";

const TEST_PHONE = "+2348000000001";
const TEST_CODE = "123456";

let db: Awaited<ReturnType<typeof freshDatabase>>;

const config = (extra: Record<string, string> = {}) =>
  loadConfig({
    NODE_ENV: "test",
    LOG_LEVEL: "silent",
    JWT_SECRET: "test-secret-that-is-at-least-32-characters-long",
    OTP_TEST_NUMBERS: `${TEST_PHONE}:${TEST_CODE},+2348000000002:654321,+2348000000003:111222`,
    ...extra,
  });

/** Each request can come from its own IP so per-IP limits don't interfere unless a test wants them to. */
let ip = 0;
const nextIp = () => `10.0.${Math.floor(++ip / 250)}.${ip % 250}`;

async function newApp(extra: Record<string, string> = {}) {
  return buildApp(config(extra), db.pool);
}

async function signIn(app: FastifyInstance, phone = TEST_PHONE, code = TEST_CODE) {
  const req = await app.inject({ method: "POST", url: "/auth/otp/request", payload: { phone }, remoteAddress: nextIp() });
  expect(req.statusCode).toBe(202);
  const res = await app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone, code }, remoteAddress: nextIp() });
  expect(res.statusCode).toBe(200);
  return res.json() as { accessToken: string; refreshToken: string; user: { id: string; hasPin: boolean } };
}

const bearer = (token: string) => ({ authorization: `Bearer ${token}` });

beforeAll(async () => {
  db = await freshDatabase();
});
afterAll(async () => db.drop());
// Each test starts without earlier codes, so per-phone limits only bite where a test checks them.
beforeEach(async () => {
  await db.pool.query("delete from otp_challenges");
});

describe("one-time codes", () => {
  it("refuse phones outside the beta whitelist", async () => {
    const app = await newApp();
    const res = await app.inject({ method: "POST", url: "/auth/otp/request", payload: { phone: "0803 999 9999" } });
    expect(res.statusCode).toBe(403);
    expect(res.json().error.code).toBe("phone_not_in_beta");
  });

  it("explain invalid phone numbers", async () => {
    const app = await newApp();
    const res = await app.inject({ method: "POST", url: "/auth/otp/request", payload: { phone: "12345" } });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message).toMatch(/Nigerian mobile number/);
  });

  it("accept local formats and create the user on first sign-in", async () => {
    const app = await newApp();
    const req = await app.inject({ method: "POST", url: "/auth/otp/request", payload: { phone: "0800 000 0001" } });
    expect(req.statusCode).toBe(202);
    expect(req.json()).toMatchObject({ sentTo: "0800 000 0001", provider: "test-numbers" });

    const res = await app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: "08000000001", code: TEST_CODE } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.user).toMatchObject({ phone: TEST_PHONE, fullName: null, hasPin: false, isDemo: false });
    expect(body.accessToken).toBeTruthy();
    expect(body.refreshToken).toBeTruthy();

    // Same phone again is the same account.
    const again = await signIn(app);
    expect(again.user.id).toBe(body.user.id);
  });

  it("count down wrong codes and burn the code after five", async () => {
    const app = await newApp();
    const phone = "+2348000000002";
    await app.inject({ method: "POST", url: "/auth/otp/request", payload: { phone }, remoteAddress: nextIp() });
    for (let i = 1; i <= 5; i++) {
      const res = await app.inject({
        method: "POST",
        url: "/auth/otp/verify",
        payload: { phone, code: "000000" },
        remoteAddress: nextIp(),
      });
      expect(res.statusCode).toBe(400);
      expect(res.json().error.details.attemptsLeft).toBe(5 - i);
    }
    const right = await app.inject({
      method: "POST",
      url: "/auth/otp/verify",
      payload: { phone, code: "654321" },
      remoteAddress: nextIp(),
    });
    expect(right.statusCode).toBe(429);
    expect(right.json().error.code).toBe("too_many_attempts");
  });

  it("limit how many codes one phone can request", async () => {
    const app = await newApp();
    const phone = "+2348000000003";
    const statuses: number[] = [];
    for (let i = 0; i < 4; i++) {
      const res = await app.inject({ method: "POST", url: "/auth/otp/request", payload: { phone }, remoteAddress: nextIp() });
      statuses.push(res.statusCode);
    }
    expect(statuses).toEqual([202, 202, 202, 429]);
  });

  it("rate-limit a single IP", async () => {
    const app = await newApp();
    const statuses: number[] = [];
    for (let i = 0; i < 6; i++) {
      const res = await app.inject({
        method: "POST",
        url: "/auth/otp/request",
        payload: { phone: "0803 999 9999" },
        remoteAddress: "10.9.9.9",
      });
      statuses.push(res.statusCode);
    }
    expect(statuses.slice(0, 5).every((s) => s === 403)).toBe(true);
    expect(statuses[5]).toBe(429);
  });

  it("are stored only as an HMAC", async () => {
    const app = await newApp();
    await app.inject({ method: "POST", url: "/auth/otp/request", payload: { phone: TEST_PHONE }, remoteAddress: nextIp() });
    const { rows } = await db.pool.query("select code_hash from otp_challenges");
    expect(rows.length).toBeGreaterThan(0);
    for (const r of rows) expect(r.code_hash).not.toContain(TEST_CODE);
  });
});

describe("sessions", () => {
  it("rotate refresh tokens and revoke the family when an old one is reused", async () => {
    const app = await newApp();
    const first = await signIn(app);

    const r1 = await app.inject({ method: "POST", url: "/auth/refresh", payload: { refreshToken: first.refreshToken } });
    expect(r1.statusCode).toBe(200);
    const second = r1.json();
    expect(second.refreshToken).not.toBe(first.refreshToken);

    // Replaying the rotated token looks like theft: it fails and kills the chain.
    const replay = await app.inject({ method: "POST", url: "/auth/refresh", payload: { refreshToken: first.refreshToken } });
    expect(replay.statusCode).toBe(401);
    const afterTheft = await app.inject({ method: "POST", url: "/auth/refresh", payload: { refreshToken: second.refreshToken } });
    expect(afterTheft.statusCode).toBe(401);
  });

  it("end on logout", async () => {
    const app = await newApp();
    const s = await signIn(app);
    const out = await app.inject({ method: "POST", url: "/auth/logout", payload: { refreshToken: s.refreshToken } });
    expect(out.statusCode).toBe(204);
    const res = await app.inject({ method: "POST", url: "/auth/refresh", payload: { refreshToken: s.refreshToken } });
    expect(res.statusCode).toBe(401);
  });

  it("require a valid access token for /me", async () => {
    const app = await newApp();
    expect((await app.inject({ method: "GET", url: "/me" })).statusCode).toBe(401);
    expect((await app.inject({ method: "GET", url: "/me", headers: bearer("not-a-token") })).statusCode).toBe(401);
    const s = await signIn(app);
    const me = await app.inject({ method: "GET", url: "/me", headers: bearer(s.accessToken) });
    expect(me.statusCode).toBe(200);
    expect(me.json().phone).toBe(TEST_PHONE);
  });
});

describe("profile and PIN", () => {
  it("validate the name", async () => {
    const app = await newApp();
    const s = await signIn(app);
    const bad = await app.inject({ method: "PATCH", url: "/me", headers: bearer(s.accessToken), payload: { fullName: "Ada" } });
    expect(bad.statusCode).toBe(400);
    const good = await app.inject({
      method: "PATCH",
      url: "/me",
      headers: bearer(s.accessToken),
      payload: { fullName: "  Ada Obi  " },
    });
    expect(good.json().fullName).toBe("Ada Obi");
  });

  it("refuse weak PINs, store an argon2id hash, and only set it once", async () => {
    const app = await newApp();
    const s = await signIn(app, "+2348000000003", "111222");
    for (const weak of ["1111", "1234", "12a4", "123"]) {
      const res = await app.inject({
        method: "POST",
        url: "/me/pin",
        headers: bearer(s.accessToken),
        payload: { pin: weak },
        remoteAddress: nextIp(),
      });
      expect(res.statusCode, weak).toBe(400);
    }
    const ok = await app.inject({
      method: "POST",
      url: "/me/pin",
      headers: bearer(s.accessToken),
      payload: { pin: "2580" },
      remoteAddress: nextIp(),
    });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().hasPin).toBe(true);

    const { rows } = await db.pool.query("select pin_hash from users where id = $1", [s.user.id]);
    expect(rows[0].pin_hash).toMatch(/^\$argon2id\$/);

    const again = await app.inject({
      method: "POST",
      url: "/me/pin",
      headers: bearer(s.accessToken),
      payload: { pin: "4826" },
      remoteAddress: nextIp(),
    });
    expect(again.statusCode).toBe(409);
  });

  it("lock the PIN after five wrong tries, even for the right PIN", async () => {
    const app = await newApp();
    const s = await signIn(app);
    await app.inject({ method: "POST", url: "/me/pin", headers: bearer(s.accessToken), payload: { pin: "4826" } });

    const verify = (pin: string) =>
      app.inject({
        method: "POST",
        url: "/me/pin/verify",
        headers: bearer(s.accessToken),
        payload: { pin },
        remoteAddress: nextIp(),
      });

    expect((await verify("4826")).statusCode).toBe(204);
    for (let i = 1; i <= 4; i++) {
      const res = await verify("0001");
      expect(res.statusCode).toBe(401);
      expect(res.json().error.details.attemptsLeft).toBe(5 - i);
    }
    expect((await verify("0001")).statusCode).toBe(423);
    const locked = await verify("4826");
    expect(locked.statusCode).toBe(423);
    expect(locked.json().error.code).toBe("pin_locked");
  });
});

describe("demo login", () => {
  it("is off unless enabled", async () => {
    const app = await newApp();
    expect((await app.inject({ method: "POST", url: "/auth/demo" })).statusCode).toBe(404);
  });

  it("explains when the demo account hasn't been seeded", async () => {
    const app = await newApp({ DEMO_LOGIN_ENABLED: "true" });
    const res = await app.inject({ method: "POST", url: "/auth/demo" });
    expect(res.statusCode).toBe(503);
    expect(res.json().error.code).toBe("demo_not_seeded");
  });

  it("signs into the seeded demo account", async () => {
    await db.pool.query(
      "insert into users (phone, full_name, is_demo) values ('+2348000000000', 'Demo Member', true) on conflict do nothing",
    );
    const app = await newApp({ DEMO_LOGIN_ENABLED: "true" });
    const res = await app.inject({ method: "POST", url: "/auth/demo" });
    expect(res.statusCode).toBe(200);
    expect(res.json().user).toMatchObject({ isDemo: true, fullName: "Demo Member" });
  });
});
