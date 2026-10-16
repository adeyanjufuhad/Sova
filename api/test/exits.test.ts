import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import type { ProofStorage } from "../src/lib/storage.js";
import { freshDatabase } from "./setup/db.js";

/** In-memory stand-in for the bucket. */
class FakeStorage implements ProofStorage {
  readonly objects = new Map<string, Buffer>();
  async put(key: string, body: Buffer) {
    this.objects.set(key, body);
  }
  async viewUrl(key: string) {
    return `https://bucket.test/view/${key}`;
  }
  async exists(key: string) {
    return this.objects.has(key);
  }
  async remove(key: string) {
    this.objects.delete(key);
  }
}

const PIN = "2580";
const PEOPLE = {
  ada: { phone: "+2348000000021", name: "Ada Obi" },
  bayo: { phone: "+2348000000022", name: "Bayo Adeyemi" },
  chuka: { phone: "+2348000000023", name: "Chuka Eze" },
  dayo: { phone: "+2348000000024", name: "Dayo Ola" },
} as const;
type Person = keyof typeof PEOPLE;

let db: Awaited<ReturnType<typeof freshDatabase>>;
let app: FastifyInstance;
const storage = new FakeStorage();
const tokens = {} as Record<Person, string>;
const ids = {} as Record<Person, string>;

let ip = 0;
const nextIp = () => `10.4.${Math.floor(++ip / 250)}.${ip % 250}`;

async function call(who: Person | null, method: "GET" | "POST" | "PATCH", url: string, payload?: object) {
  const res = await app.inject({
    method,
    url,
    payload,
    remoteAddress: nextIp(),
    headers: who ? { authorization: `Bearer ${tokens[who]}` } : {},
  });
  return { status: res.statusCode, body: res.statusCode === 204 ? null : res.json() };
}

async function signIn(who: Person) {
  const p = PEOPLE[who];
  await call(null, "POST", "/auth/otp/request", { phone: p.phone });
  const signed = await call(null, "POST", "/auth/otp/verify", { phone: p.phone, code: "123456" });
  tokens[who] = signed.body.accessToken;
  ids[who] = signed.body.user.id;
  if (!signed.body.user.fullName) await call(who, "PATCH", "/me", { fullName: p.name });
  if (!signed.body.user.hasPin) await call(who, "POST", "/me/pin", { pin: PIN });
  return signed.body;
}

const startDate = () => new Date(Date.now() + 2 * 86_400_000).toISOString().slice(0, 10);

async function newCircle(admin: Person, memberCount: number) {
  const res = await call(admin, "POST", "/circles", {
    name: "Exit Test Ajo",
    contributionAmount: 5000,
    memberCount,
    cycleType: "weekly",
    startDate: startDate(),
    pin: PIN,
  });
  expect(res.status).toBe(201);
  return { id: res.body.id as string, code: res.body.inviteCode as string };
}

const join = (who: Person, code: string) => call(who, "POST", "/circles/join", { code, rulesVersion: 1, pin: PIN });

async function ledgerKinds(circleId: string) {
  const res = await call(null, "GET", `/public/circles/${circleId}/ledger`);
  return res.body.entries.map((e: { kind: string }) => e.kind) as string[];
}

beforeAll(async () => {
  db = await freshDatabase();
  const numbers = Object.values(PEOPLE).map((p) => `${p.phone}:123456`).join(",");
  app = await buildApp(
    loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent", JWT_SECRET: "test-secret-that-is-at-least-32-characters-long", OTP_TEST_NUMBERS: numbers }),
    db.pool,
    { storage },
  );
  for (const who of Object.keys(PEOPLE) as Person[]) await signIn(who);
});
afterAll(async () => db.drop());

describe("leaving a forming circle", () => {
  it("lets a member leave, opens their place and records it", async () => {
    const { id, code } = await newCircle("ada", 4);
    expect((await join("bayo", code)).status).toBe(200);

    expect((await call("bayo", "POST", `/circles/${id}/leave`, { pin: "1111" })).body.error.code).toBe("wrong_pin");
    await db.pool.query("select reset_pin_attempts($1)", [ids.bayo]);

    expect((await call("bayo", "POST", `/circles/${id}/leave`, { pin: PIN })).status).toBe(204);
    expect((await call("bayo", "GET", `/circles/${id}`)).status).toBe(404);
    expect((await call("ada", "GET", `/circles/${id}`)).body.membersJoined).toBe(1);
    expect(await ledgerKinds(id)).toContain("member_left");

    const inbox = await call("ada", "GET", "/me/notifications");
    expect(inbox.body.items[0].title).toBe("Bayo left Exit Test Ajo");

    // Their old acceptance went with them, so joining again works.
    expect((await join("bayo", code)).status).toBe(200);
  });

  it("refuses the admin, non-members and circles that have started", async () => {
    const { id, code } = await newCircle("ada", 2);
    expect((await call("ada", "POST", `/circles/${id}/leave`, { pin: PIN })).body.error.code).toBe("admin_cannot_leave");
    expect((await call("chuka", "POST", `/circles/${id}/leave`, { pin: PIN })).status).toBe(404);

    expect((await join("chuka", code)).body.status).toBe("active");
    expect((await call("chuka", "POST", `/circles/${id}/leave`, { pin: PIN })).body.error.code).toBe("circle_started");
  });
});

describe("cancelling a forming circle", () => {
  it("lets only the admin cancel, records it and closes the invite code", async () => {
    const { id, code } = await newCircle("ada", 4);
    await join("dayo", code);

    expect((await call("dayo", "POST", `/circles/${id}/cancel`, { pin: PIN })).body.error.code).toBe("not_admin");

    const res = await call("ada", "POST", `/circles/${id}/cancel`, { pin: PIN });
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("cancelled");
    expect(await ledgerKinds(id)).toContain("circle_cancelled");

    const inbox = await call("dayo", "GET", "/me/notifications");
    expect(inbox.body.items[0].title).toBe("Exit Test Ajo was cancelled");

    expect((await join("chuka", code)).body.error.code).toBe("circle_cancelled");
    expect((await call("ada", "POST", `/circles/${id}/cancel`, { pin: PIN })).body.error.code).toBe("circle_started");
  });

  it("doesn't count a cancelled circle towards the Sova Score", async () => {
    const { rows } = await db.pool.query("select active_cycles from sova_score_now($1)", [ids.dayo]);
    expect(rows[0].active_cycles).toBe(0);
  });
});

describe("deleting an account", () => {
  it("refuses while a circle of yours is forming (as admin) or running", async () => {
    const forming = await newCircle("chuka", 3);
    expect((await call("chuka", "POST", "/me/delete", { pin: PIN })).body.error.code).toBe("admin_of_forming");
    await call("chuka", "POST", `/circles/${forming.id}/cancel`, { pin: PIN });

    // chuka is in the running two-person circle from the leaving tests.
    expect((await call("chuka", "POST", "/me/delete", { pin: PIN })).body.error.code).toBe("circle_in_progress");
  });

  it("refuses the shared demo account", async () => {
    await db.pool.query("update users set is_demo = true where id = $1", [ids.dayo]);
    expect((await call("dayo", "POST", "/me/delete", { pin: PIN })).body.error.code).toBe("demo_account");
    await db.pool.query("update users set is_demo = false where id = $1", [ids.dayo]);
  });

  it("removes personal data and photos, leaves forming circles and frees the phone number", async () => {
    // dayo: a finished circle with a receipt photo, plus a forming circle run by ada.
    const done = await newCircle("ada", 2);
    await join("dayo", done.code);
    const key = `proofs/${done.id}/1/${ids.dayo}/photo.jpg`;
    storage.objects.set(key, Buffer.from("jpeg"));
    await db.pool.query(
      `insert into contributions (round_id, group_id, user_id, amount, status, payer_confirmed, payer_confirmed_at, proof_url)
       select r.id, r.group_id, $2, 5000, 'payer_confirmed', true, now(), $3 from rounds r where r.group_id = $1 and r.round_number = 1
       on conflict (round_id, user_id) do update set proof_url = excluded.proof_url`,
      [done.id, ids.dayo, key],
    );
    await db.pool.query("update groups set status = 'completed' where id = $1", [done.id]);
    const forming = await newCircle("ada", 4);
    await join("dayo", forming.code);

    expect((await call("dayo", "POST", "/me/delete", { pin: PIN })).status).toBe(204);

    const { rows } = await db.pool.query(
      "select phone, full_name, pin_hash, account_number, deleted_at from users where id = $1",
      [ids.dayo],
    );
    expect(rows[0]).toMatchObject({ phone: null, full_name: null, pin_hash: null, account_number: null });
    expect(rows[0].deleted_at).not.toBeNull();
    expect(storage.objects.has(key)).toBe(false);
    expect((await db.pool.query("select count(*)::int as n from sessions where user_id = $1", [ids.dayo])).rows[0].n).toBe(0);
    expect((await call("ada", "GET", `/circles/${forming.id}`)).body.membersJoined).toBe(1);
    expect((await call("dayo", "GET", "/me")).status).toBe(401);

    // The finished circle's record stays, with the member shown without a name or phone.
    const finished = await call("ada", "GET", `/circles/${done.id}`);
    expect(finished.body.members.find((m: { id: string }) => m.id === ids.dayo)).toMatchObject({ name: null, phone: null });

    // The number can sign up again as a new account.
    const oldId = ids.dayo;
    const again = await signIn("dayo");
    expect(again.user.id).not.toBe(oldId);
    expect(again.user.fullName).toBeNull();
  });
});
