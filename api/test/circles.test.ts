import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { commitmentOf, drawOrder } from "../src/lib/draw.js";
import { freshDatabase } from "./setup/db.js";

const PIN = "2580";
const PEOPLE = {
  ada: { phone: "+2348000000011", name: "Ada Obi" },
  bayo: { phone: "+2348000000012", name: "Bayo Adeyemi" },
  chuka: { phone: "+2348000000013", name: "Chuka Eze" },
  dayo: { phone: "+2348000000014", name: "Dayo Ola" },
  nameless: { phone: "+2348000000015", name: null },
} as const;
type Person = keyof typeof PEOPLE;

let db: Awaited<ReturnType<typeof freshDatabase>>;
let app: FastifyInstance;
const tokens = {} as Record<Person, string>;
const ids = {} as Record<Person, string>;

let ip = 0;
const nextIp = () => `10.1.${Math.floor(++ip / 250)}.${ip % 250}`;

async function call(who: Person | null, method: "GET" | "POST" | "PATCH" | "PUT", url: string, payload?: object) {
  const res = await app.inject({
    method,
    url,
    payload,
    remoteAddress: nextIp(),
    headers: who ? { authorization: `Bearer ${tokens[who]}` } : {},
  });
  return { status: res.statusCode, body: res.json() };
}

function nextWeekday(offsetDays = 0) {
  const d = new Date(Date.now() + offsetDays * 86_400_000 + 3_600_000); // Lagos is UTC+1
  return d.toISOString().slice(0, 10);
}

const newCircle = (overrides: object = {}) => ({
  name: "Tech Hub Esusu",
  contributionAmount: 10000,
  memberCount: 3,
  cycleType: "weekly",
  startDate: nextWeekday(1),
  rules: { lateFee: 500, graceDays: 1, earlyExitPolicy: "find_replacement" },
  pin: PIN,
  ...overrides,
});

beforeAll(async () => {
  db = await freshDatabase();
  const numbers = Object.values(PEOPLE).map((p) => `${p.phone}:123456`).join(",");
  app = await buildApp(
    loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent", JWT_SECRET: "test-secret-that-is-at-least-32-characters-long", OTP_TEST_NUMBERS: numbers }),
    db.pool,
  );
  for (const [key, p] of Object.entries(PEOPLE) as [Person, (typeof PEOPLE)[Person]][]) {
    await call(null, "POST", "/auth/otp/request", { phone: p.phone });
    const signed = await call(null, "POST", "/auth/otp/verify", { phone: p.phone, code: "123456" });
    tokens[key] = signed.body.accessToken;
    ids[key] = signed.body.user.id;
    if (p.name) await call(key, "PATCH", "/me", { fullName: p.name });
    await call(key, "POST", "/me/pin", { pin: PIN });
  }
});
afterAll(async () => db.drop());

describe("bank details", () => {
  it("lists banks and saves where a member receives their payout", async () => {
    const banks = await call("ada", "GET", "/banks");
    expect(banks.body.banks.map((b: { name: string }) => b.name)).toContain("OPay");

    const saved = await call("ada", "PUT", "/me/bank", { bankName: "opay", accountNumber: "9061234567", accountName: "Ada Obi" });
    expect(saved.status).toBe(200);
    expect(saved.body.bank).toEqual({ bankName: "OPay", accountNumber: "9061234567", accountName: "Ada Obi" });

    const unknown = await call("ada", "PUT", "/me/bank", { bankName: "Bank of Nowhere", accountNumber: "9061234567", accountName: "Ada Obi" });
    expect(unknown.body.error.code).toBe("unknown_bank");
  });
});

describe("circle lifecycle", () => {
  let circleId: string;
  let code: string;

  it("creates a forming circle with a draw commitment and the admin as first member", async () => {
    const res = await call("ada", "POST", "/circles", newCircle());
    expect(res.status).toBe(201);
    const c = res.body;
    circleId = c.id;
    code = c.inviteCode;
    expect(code).toMatch(/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$/);
    expect(c).toMatchObject({ status: "forming", membersJoined: 1, payoutAmount: 20000, isAdmin: true, currentRound: null });
    expect(c.draw.commitment).toMatch(/^[0-9a-f]{64}$/);
    expect(c.draw.seed).toBeNull();
    expect(c.rules).toMatchObject({ version: 1, lateFee: 500, acceptedByMe: true });
  });

  it("refuses bad input, missing names and wrong PINs", async () => {
    expect((await call("ada", "POST", "/circles", newCircle({ startDate: "2020-01-01" }))).status).toBe(400);
    expect((await call("ada", "POST", "/circles", newCircle({ memberCount: 31 }))).status).toBe(400);
    expect((await call("nameless", "POST", "/circles", newCircle())).body.error.code).toBe("profile_incomplete");
    expect((await call("ada", "POST", "/circles", newCircle({ pin: "9999" }))).body.error.code).toBe("wrong_pin");
    await db.pool.query("select reset_pin_attempts($1)", [ids.ada]);
  });

  it("hides circles from people who aren't in them", async () => {
    expect((await call("chuka", "GET", `/circles/${circleId}`)).status).toBe(404);
  });

  it("previews by invite code, in any case and with spaces", async () => {
    const res = await call("bayo", "GET", `/circles/preview/${code.toLowerCase().slice(0, 3)}%20${code.slice(3)}`);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ name: "Tech Hub Esusu", alreadyMember: false, isFull: false, adminName: "Ada Obi" });
    expect(res.body.members).toEqual([{ id: ids.ada, name: "Ada Obi" }]);
    expect((await call("bayo", "GET", "/circles/preview/ZZZZZZ")).status).toBe(404);
  });

  it("joins with a voucher after accepting the current rules", async () => {
    const stale = await call("bayo", "POST", "/circles/join", { code, rulesVersion: 2, pin: PIN });
    expect(stale.body.error.code).toBe("rules_changed");

    const res = await call("bayo", "POST", "/circles/join", { code, voucherId: ids.ada, rulesVersion: 1, pin: PIN });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ status: "forming", membersJoined: 2 });
    expect(res.body.members.find((m: { id: string }) => m.id === ids.bayo).vouchedBy).toEqual({ id: ids.ada, name: "Ada Obi" });

    const again = await call("bayo", "POST", "/circles/join", { code, rulesVersion: 1, pin: PIN });
    expect(again.body.error.code).toBe("already_member");
  });

  it("draws the turns and opens turn 1 when the last member joins", async () => {
    const res = await call("chuka", "POST", "/circles/join", { code, rulesVersion: 1, pin: PIN });
    const c = res.body;
    expect(c.status).toBe("active");

    // The revealed seed matches the commitment published at creation, and reproduces the order.
    expect(commitmentOf(c.draw.seed)).toBe(c.draw.commitment);
    const byPosition = [...c.members].sort((a, b) => a.position - b.position).map((m: { id: string }) => m.id);
    expect(drawOrder(c.draw.seed, [ids.ada, ids.bayo, ids.chuka], ids.ada, false)).toEqual(byPosition);

    expect(c.currentRound).toMatchObject({ number: 1, payoutAmount: 20000 });
    expect(c.currentRound.collector.id).toBe(byPosition[0]);
    expect(c.currentRound.contributions.map((x: { status: string }) => x.status)).toEqual(["unpaid", "unpaid"]);

    expect((await call("dayo", "POST", "/circles/join", { code, rulesVersion: 1, pin: PIN })).body.error.code).toBe("circle_started");
  });

  /** Plays one turn: everyone except `skip` pays and is confirmed, then the collector confirms `received`. */
  async function playTurn(number: number, received: number, skip: string[] = []) {
    const detail = (await call("ada", "GET", `/circles/${circleId}`)).body;
    expect(detail.currentRound.number).toBe(number);
    const collector = (Object.keys(ids) as Person[]).find((k) => ids[k] === detail.currentRound.collector.id)!;
    const payers = (Object.keys(ids) as Person[]).filter(
      (k) => detail.members.some((m: { id: string }) => m.id === ids[k]) && k !== collector && !skip.includes(ids[k]),
    );

    expect((await call(collector, "POST", `/circles/${circleId}/rounds/${number}/pay`, { pin: PIN })).body.error.code).toBe("own_turn");

    for (const payer of payers) {
      const paid = await call(payer, "POST", `/circles/${circleId}/rounds/${number}/pay`, { bankReference: `FT${number}${payer}`, pin: PIN });
      expect(paid.status).toBe(200);
      const mine = paid.body.currentRound.contributions.find((x: { userId: string }) => x.userId === ids[payer]);
      expect(mine).toMatchObject({ status: "payer_confirmed", bankReference: `FT${number}${payer}` });

      expect((await call(payer, "POST", `/contributions/${mine.id}/confirm`, { pin: PIN })).body.error.code).toBe("not_collector");
      const confirmed = await call(collector, "POST", `/contributions/${mine.id}/confirm`, { pin: PIN });
      expect(confirmed.status).toBe(200);
    }

    const payout = await call(collector, "POST", `/circles/${circleId}/rounds/${number}/payout`, { amount: received, pin: PIN });
    expect(payout.status).toBe(200);
    return payout.body;
  }

  it("advances to the next turn when the collector confirms the full payout", async () => {
    const result = await playTurn(1, 20000);
    expect(result).toMatchObject({ shortfall: 0, disputeId: null, nextRound: 2 });
    expect(result.circle.currentRound.number).toBe(2);
  });

  it("opens a dispute on a short payout and still moves on", async () => {
    const detail = (await call("ada", "GET", `/circles/${circleId}`)).body;
    const missing = detail.currentRound.contributions[0].userId;
    const result = await playTurn(2, 10000, [missing]);
    expect(result).toMatchObject({ shortfall: 10000, nextRound: 3 });
    expect(result.circle.openDisputes).toBe(1);

    const { rows } = await db.pool.query("select reason, status from disputes where id = $1", [result.disputeId]);
    expect(rows[0]).toMatchObject({ status: "open" });
    expect(rows[0].reason).toBe("Turn 2 payout was ₦10,000 short: expected ₦20,000, received ₦10,000.");
  });

  it("completes the circle after the last turn and updates Sova Scores", async () => {
    const result = await playTurn(3, 20000);
    expect(result).toMatchObject({ shortfall: 0, nextRound: null });
    expect(result.circle).toMatchObject({ status: "completed", currentRound: null });

    const history = await call("bayo", "GET", `/circles/${circleId}/rounds`);
    expect(history.body.rounds.map((r: { status: string }) => r.status)).toEqual(["completed", "completed", "completed"]);
    expect(history.body.rounds[1]).toMatchObject({ payoutReceived: 10000, paidCount: 1, confirmedCount: 1 });

    // The detail carries the full history for receipts and the member's record.
    const detail = (await call("bayo", "GET", `/circles/${circleId}`)).body;
    expect(detail.rounds).toHaveLength(3);
    expect(detail.contributions).toHaveLength(5); // 2 + 1 + 2 payments
    expect(detail.contributions.every((x: { status: string }) => x.status === "fully_confirmed")).toBe(true);

    const scores = await db.pool.query("select count(distinct user_id)::int as n from scores");
    expect(scores.rows[0].n).toBe(3);
  });

  it("lists the member's circles", async () => {
    const res = await call("chuka", "GET", "/circles");
    expect(res.body.circles).toHaveLength(1);
    expect(res.body.circles[0]).toMatchObject({ id: circleId, status: "completed", currentRound: null });
  });
});

describe("admin collect-last pledge", () => {
  it("puts the admin last whatever the draw says", async () => {
    const created = await call("dayo", "POST", "/circles", newCircle({ memberCount: 2, adminCollectsLast: true }));
    const code = created.body.inviteCode;
    const joined = await call("ada", "POST", "/circles/join", { code, rulesVersion: 1, pin: PIN });
    expect(joined.body.status).toBe("active");
    expect(joined.body.members.find((m: { id: string }) => m.id === ids.dayo).position).toBe(2);
    expect(joined.body.currentRound.collector.id).toBe(ids.ada);
  });
});
