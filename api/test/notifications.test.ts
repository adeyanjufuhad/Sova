import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { freshDatabase } from "./setup/db.js";

const PIN = "2580";
const PEOPLE = {
  ada: { phone: "+2348000000051", name: "Ada Obi" },
  bayo: { phone: "+2348000000052", name: "Bayo Adeyemi" },
  chuka: { phone: "+2348000000053", name: "Chuka Eze" },
} as const;
type Person = keyof typeof PEOPLE;

let db: Awaited<ReturnType<typeof freshDatabase>>;
let app: FastifyInstance;
const tokens = {} as Record<Person, string>;
const ids = {} as Record<Person, string>;
let circleId: string;
let collector: Person;
let payers: Person[];

let ip = 0;
const nextIp = () => `10.5.${Math.floor(++ip / 250)}.${ip % 250}`;
const nameOf = (id: string) => (Object.keys(ids) as Person[]).find((k) => ids[k] === id)!;

async function call(who: Person, method: "GET" | "POST" | "PATCH" | "PUT", url: string, payload?: object) {
  const res = await app.inject({ method, url, payload, remoteAddress: nextIp(), headers: { authorization: `Bearer ${tokens[who]}` } });
  return { status: res.statusCode, body: res.body ? res.json() : null };
}
const inbox = async (who: Person) => (await call(who, "GET", "/me/notifications")).body;

beforeAll(async () => {
  db = await freshDatabase();
  const numbers = Object.values(PEOPLE).map((p) => `${p.phone}:123456`).join(",");
  app = await buildApp(
    loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent", JWT_SECRET: "test-secret-that-is-at-least-32-characters-long", OTP_TEST_NUMBERS: numbers }),
    db.pool,
  );
  for (const [key, p] of Object.entries(PEOPLE) as [Person, (typeof PEOPLE)[Person]][]) {
    await app.inject({ method: "POST", url: "/auth/otp/request", payload: { phone: p.phone }, remoteAddress: nextIp() });
    const signed = (await app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: p.phone, code: "123456" }, remoteAddress: nextIp() })).json();
    tokens[key] = signed.accessToken;
    ids[key] = signed.user.id;
    await call(key, "PATCH", "/me", { fullName: p.name });
    await call(key, "POST", "/me/pin", { pin: PIN });
  }
  // Starts tomorrow, so turn 1 is due tomorrow.
  const tomorrow = new Date(Date.now() + 86_400_000 + 3_600_000).toISOString().slice(0, 10);
  const created = await call("ada", "POST", "/circles", {
    name: "Market Friends", contributionAmount: 5000, memberCount: 3, cycleType: "weekly", startDate: tomorrow, pin: PIN,
  });
  circleId = created.body.id;
  for (const p of ["bayo", "chuka"] as const) {
    await call(p, "POST", "/circles/join", { code: created.body.inviteCode, voucherId: ids.ada, rulesVersion: 1, pin: PIN });
  }
  const c = (await call("ada", "GET", `/circles/${circleId}`)).body;
  collector = nameOf(c.currentRound.collector.id);
  payers = (["ada", "bayo", "chuka"] as Person[]).filter((p) => p !== collector);
});
afterAll(async () => db.drop());

describe("notifications", () => {
  it("tells everyone when a turn opens, and reminds payers what's due", async () => {
    const mine = await inbox(collector);
    expect(mine.items[0]).toMatchObject({ type: "turn_opened", title: "It's your turn to collect ₦10,000", read: false });
    expect(mine.items[0].link).toBe(`/circle/${circleId}`);

    const payer = await inbox(payers[0]!);
    expect(payer.items[0].title).toMatch(/^Turn 1: pay \w+ ₦5,000$/);
    expect(payer.reminders).toEqual([
      expect.objectContaining({ kind: "due", title: expect.stringMatching(/^Pay \w+ ₦5,000$/), link: `/circle/${circleId}/pay` }),
    ]);
    expect(payer.reminders[0].message).toContain("Due tomorrow");
    expect(payer.badge).toBe(2); // one unread notification + one reminder
  });

  it("asks the collector to confirm, then tells the payer it was confirmed", async () => {
    const payer = payers[0]!;
    await call(payer, "POST", `/circles/${circleId}/rounds/1/pay`, { bankReference: "FT123", pin: PIN });
    expect((await inbox(payer)).reminders).toEqual([]);

    const col = await inbox(collector);
    expect(col.items[0]).toMatchObject({ type: "payment_marked", title: `${PEOPLE[payer].name.split(" ")[0]} marked ₦5,000 as sent` });
    expect(col.reminders).toEqual([expect.objectContaining({ kind: "confirm", title: "1 payment to confirm" })]);

    const c = (await call(collector, "GET", `/circles/${circleId}`)).body;
    const contribution = c.currentRound.contributions.find((x: { userId: string }) => x.userId === ids[payer]);
    await call(collector, "POST", `/contributions/${contribution.id}/confirm`, { pin: PIN });
    const after = await inbox(payer);
    expect(after.items[0]).toMatchObject({ type: "payment_confirmed" });
    expect(after.items[0].link).toMatch(new RegExp(`^/circle/${circleId}/receipt/`));
  });

  it("marks everything read when the list is opened", async () => {
    const payer = payers[1]!;
    expect((await call(payer, "POST", "/me/notifications/read")).status).toBe(204);
    const after = await inbox(payer);
    expect(after.items.every((n: { read: boolean }) => n.read)).toBe(true);
    expect(after.badge).toBe(after.reminders.length);
  });
});

describe("settings", () => {
  it("changes the PIN only with the current one, and refuses easy PINs", async () => {
    expect((await call("bayo", "POST", "/me/pin/change", { currentPin: "9999", newPin: "4826" })).body.error.code).toBe("wrong_pin");
    await db.pool.query("select reset_pin_attempts($1)", [ids.bayo]);
    expect((await call("bayo", "POST", "/me/pin/change", { currentPin: PIN, newPin: "1234" })).status).toBe(400);
    expect((await call("bayo", "POST", "/me/pin/change", { currentPin: PIN, newPin: PIN })).body.error.code).toBe("same_pin");
    expect((await call("bayo", "POST", "/me/pin/change", { currentPin: PIN, newPin: "4826" })).status).toBe(204);
    expect((await call("bayo", "POST", "/me/pin/verify", { pin: "4826" })).status).toBe(204);
    expect((await call("bayo", "POST", "/me/pin/verify", { pin: PIN })).body.error.code).toBe("wrong_pin");
  });

  it("needs the PIN to change where payouts go", async () => {
    const bank = { bankName: "OPay", accountNumber: "9061234567", accountName: "Chuka Eze" };
    expect((await call("chuka", "PUT", "/me/bank", bank)).status).toBe(400);
    expect((await call("chuka", "PUT", "/me/bank", { ...bank, pin: "9999" })).body.error.code).toBe("wrong_pin");
    await db.pool.query("select reset_pin_attempts($1)", [ids.chuka]);
    const saved = await call("chuka", "PUT", "/me/bank", { ...bank, pin: PIN });
    expect(saved.body.bank).toEqual({ bankName: "OPay", accountNumber: "9061234567", accountName: "Chuka Eze" });
  });
});
