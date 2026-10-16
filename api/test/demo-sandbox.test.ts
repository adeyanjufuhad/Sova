import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { commitmentOf, drawOrder } from "../src/lib/draw.js";
import { claimDemoSandbox, createDemoSandbox, DEMO_PIN, topUpDemoSpares } from "../src/seed/demo.js";
import { freshDatabase } from "./setup/db.js";

const REAL = "+2348031234567";

let db: Awaited<ReturnType<typeof freshDatabase>>;
let app: FastifyInstance;
const tokens: Record<string, string> = {};
const ids: Record<string, string> = {};

let ip = 0;
const nextIp = () => `10.5.${Math.floor(++ip / 250)}.${ip % 250}`;

async function call(who: string | null, method: "GET" | "POST" | "PATCH", url: string, payload?: object) {
  const res = await app.inject({
    method,
    url,
    payload,
    remoteAddress: nextIp(),
    headers: who ? { authorization: `Bearer ${tokens[who]}` } : {},
  });
  return { status: res.statusCode, body: res.statusCode === 204 ? null : res.json() };
}

/** "Try the demo" as a new visitor. */
async function visit(who: string) {
  const res = await call(null, "POST", "/auth/demo");
  expect(res.status).toBe(200);
  tokens[who] = res.body.accessToken;
  ids[who] = res.body.user.id;
}

const sandboxOf = async (who: string) =>
  (await db.pool.query<{ sandbox_id: string }>("select sandbox_id from users where id = $1", [ids[who]])).rows[0]!.sandbox_id;

async function myCircle(who: string, name: string) {
  const { body } = await call(who, "GET", "/circles");
  return (body.circles as { id: string; name: string }[]).find((c) => c.name === name)!.id;
}

beforeAll(async () => {
  db = await freshDatabase();
  app = await buildApp(
    loadConfig({
      NODE_ENV: "test",
      LOG_LEVEL: "silent",
      JWT_SECRET: "test-secret-that-is-at-least-32-characters-long",
      DEMO_LOGIN_ENABLED: "true",
      DEMO_SPARES: "0",
      OTP_TEST_NUMBERS: `${REAL}:123456`,
    }),
    db.pool,
  );
  await visit("first");
  await visit("second");
  await call(null, "POST", "/auth/otp/request", { phone: REAL });
  tokens.real = (await call(null, "POST", "/auth/otp/verify", { phone: REAL, code: "123456" })).body.accessToken;
  await call("real", "PATCH", "/me", { fullName: "Real Person" });
  await call("real", "POST", "/me/pin", { pin: "4826" });
});
afterAll(async () => db.drop());

describe("private demos", () => {
  it("give every visitor their own copy of the whole demo", async () => {
    expect(ids.first).not.toBe(ids.second);
    const first = await call("first", "GET", "/circles");
    const second = await call("second", "GET", "/circles");
    expect(first.body.circles.map((c: { name: string }) => c.name).sort()).toEqual(
      ["Church Adashe", "Office Esusu", "Unilag Class of '24 Ajo", "Yaba Traders Circle"],
    );
    const firstIds = first.body.circles.map((c: { id: string }) => c.id);
    for (const c of second.body.circles) expect(firstIds).not.toContain(c.id);
  });

  it("keep one visitor's actions out of another's demo", async () => {
    const office = await myCircle("first", "Office Esusu");
    const paid = await call("first", "POST", `/circles/${office}/rounds/3/pay`, { bankReference: "FT26DEMO1", pin: DEMO_PIN });
    expect(paid.status).toBe(200);

    const theirs = await call("second", "GET", `/circles/${await myCircle("second", "Office Esusu")}`);
    const ada = theirs.body.currentRound.contributions.find((c: { userId: string }) => c.userId === ids.second);
    expect(ada.status).toBe("unpaid");
  });

  it("keep invite codes inside their own world", async () => {
    const mine = await call("first", "GET", "/circles/preview/T7KP9Q");
    const techHub = await db.pool.query<{ id: string }>(
      "select id from groups where invite_code = 'T7KP9Q' and sandbox_id = $1",
      [await sandboxOf("first")],
    );
    expect(mine.body.id).toBe(techHub.rows[0]!.id);

    // A real account can't see or join a demo's circles.
    expect((await call("real", "GET", "/circles/preview/T7KP9Q")).status).toBe(404);
    const join = await call("real", "POST", "/circles/join", { code: "T7KP9Q", rulesVersion: 1, pin: "4826" });
    expect(join.body.error.code).toBe("circle_not_found");
  });

  it("verify like the shared demo: every started circle's draw checks out", async () => {
    const { rows } = await db.pool.query<{
      status: string;
      commitment: string;
      seed: string;
      admin_id: string;
      admin_collects_last: boolean;
      members: string[];
    }>(
      `select g.status, d.commitment, d.seed, g.admin_id, g.admin_collects_last,
              array(select user_id::text from group_members m where m.group_id = g.id order by m.payout_position) as members
         from groups g join circle_draws d on d.group_id = g.id where g.sandbox_id = $1`,
      [await sandboxOf("second")],
    );
    expect(rows).toHaveLength(5);
    for (const r of rows) {
      expect(commitmentOf(r.seed)).toBe(r.commitment);
      if (r.status !== "forming") expect(drawOrder(r.seed, r.members, r.admin_id, r.admin_collects_last)).toEqual(r.members);
    }
  });

  it("are never published as ledger anchors", async () => {
    const ledger = await db.pool.query<{ n: number }>("select count(*)::int as n from ledger_entries");
    expect(ledger.rows[0]!.n).toBeGreaterThan(0);
    expect((await call(null, "GET", "/public/chain-heads")).body.heads).toEqual([]);
  });

  it("keep the demo account's protections", async () => {
    expect((await call("first", "PATCH", "/me", { fullName: "Someone Else" })).status).toBe(403);
    expect((await call("first", "POST", "/me/delete", { pin: DEMO_PIN })).body.error.code).toBe("demo_account");
    const office = await myCircle("first", "Office Esusu");
    const handover = await call("first", "POST", `/circles/${office}/handovers`, { phone: REAL, pin: DEMO_PIN });
    expect(handover.body.error.code).toBe("demo_handover");
  });

  it("are removed once they expire, when the next visitor arrives", async () => {
    const sandbox = await sandboxOf("first");
    await db.pool.query("update demo_sandboxes set expires_at = now() - interval '1 hour' where id = $1", [sandbox]);
    await visit("third");

    const left = await db.pool.query<{ users: number; groups: number; sandboxes: number }>(
      `select (select count(*)::int from users where sandbox_id = $1) as users,
              (select count(*)::int from groups where sandbox_id = $1) as groups,
              (select count(*)::int from demo_sandboxes where id = $1) as sandboxes`,
      [sandbox],
    );
    expect(left.rows[0]).toEqual({ users: 0, groups: 0, sandboxes: 0 });
    expect((await call("first", "GET", "/me")).status).toBe(401);
    expect((await call("second", "GET", "/me")).status).toBe(200);
  });

  it("stop at the limit instead of growing without bound", async () => {
    const live = (await db.pool.query<{ n: number }>("select count(*)::int as n from demo_sandboxes")).rows[0]!.n;
    expect(await createDemoSandbox(db.pool, { limit: live })).toBeNull();
  });
});

describe("spare demos", () => {
  const spares = async () =>
    (await db.pool.query<{ n: number }>("select count(*)::int as n from demo_sandboxes where claimed_at is null")).rows[0]!.n;

  it("are built ahead and handed out whole, one visitor each", async () => {
    expect(await spares()).toBe(0);
    expect(await topUpDemoSpares(db.pool, 1)).toBe(1);
    expect(await topUpDemoSpares(db.pool, 1)).toBe(0); // already one ready

    const spareAda = (
      await db.pool.query<{ id: string }>(
        "select u.id from users u join demo_sandboxes s on s.id = u.sandbox_id where s.claimed_at is null and u.is_demo",
      )
    ).rows[0]!.id;
    const res = await call(null, "POST", "/auth/demo");
    expect(res.body.user.id).toBe(spareAda);
    expect(await spares()).toBe(0);

    // Claiming starts the visitor's own day.
    const { rows } = await db.pool.query<{ hours: number }>(
      `select (extract(epoch from s.expires_at - now()) / 3600)::float8 as hours
         from demo_sandboxes s join users u on u.sandbox_id = s.id where u.id = $1`,
      [spareAda],
    );
    expect(rows[0]!.hours).toBeGreaterThan(23);

    // With no spare ready, the next visitor still gets a copy, built on the spot.
    expect((await call(null, "POST", "/auth/demo")).status).toBe(200);
  });

  it("are thrown away unclaimed after a few hours", async () => {
    await topUpDemoSpares(db.pool, 1);
    await db.pool.query("update demo_sandboxes set expires_at = now() - interval '1 minute' where claimed_at is null");
    expect(await claimDemoSandbox(db.pool)).toBeNull();
    await db.pool.query("select purge_demo_sandboxes()");
    expect(await spares()).toBe(0);
  });
});
