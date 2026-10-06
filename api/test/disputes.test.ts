import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { freshDatabase } from "./setup/db.js";

const PIN = "2580";
const PEOPLE = {
  ada: { phone: "+2348000000021", name: "Ada Obi" },
  bayo: { phone: "+2348000000022", name: "Bayo Adeyemi" },
  chuka: { phone: "+2348000000023", name: "Chuka Eze" },
  dayo: { phone: "+2348000000024", name: "Dayo Ola" },
  efe: { phone: "+2348000000025", name: "Efe Udo" },
  outsider: { phone: "+2348000000026", name: "Out Sider" },
} as const;
type Person = keyof typeof PEOPLE;
const CIRCLE: Person[] = ["ada", "bayo", "chuka", "dayo", "efe"];

let db: Awaited<ReturnType<typeof freshDatabase>>;
let app: FastifyInstance;
const tokens = {} as Record<Person, string>;
const ids = {} as Record<Person, string>;
const nameOf = (id: string) => (Object.keys(ids) as Person[]).find((k) => ids[k] === id)!;

let ip = 0;
const nextIp = () => `10.2.${Math.floor(++ip / 250)}.${ip % 250}`;

async function call(who: Person, method: "GET" | "POST" | "PATCH", url: string, payload?: object) {
  const res = await app.inject({ method, url, payload, remoteAddress: nextIp(), headers: { authorization: `Bearer ${tokens[who]}` } });
  return { status: res.statusCode, body: res.json() };
}

/** Turn 1's collector, and the other four members (the payers). */
let circleId: string;
let collector: Person;
let payers: Person[];

const contributionOf = async (payer: Person) => {
  const c = (await call(payer, "GET", `/circles/${circleId}`)).body;
  return c.currentRound.contributions.find((x: { userId: string }) => x.userId === ids[payer]);
};
const pay = (payer: Person) => call(payer, "POST", `/circles/${circleId}/rounds/1/pay`, { bankReference: `REF-${payer}`, pin: PIN });

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

  const tomorrow = new Date(Date.now() + 86_400_000 + 3_600_000).toISOString().slice(0, 10);
  const created = await call("ada", "POST", "/circles", {
    name: "Market Friends",
    contributionAmount: 5000,
    memberCount: 5,
    cycleType: "weekly",
    startDate: tomorrow,
    pin: PIN,
  });
  circleId = created.body.id;
  for (const p of CIRCLE.slice(1)) {
    await call(p, "POST", "/circles/join", { code: created.body.inviteCode, voucherId: ids.ada, rulesVersion: 1, pin: PIN });
  }
  const started = (await call("ada", "GET", `/circles/${circleId}`)).body;
  collector = nameOf(started.currentRound.collector.id);
  payers = CIRCLE.filter((p) => p !== collector);
});
afterAll(async () => db.drop());

describe("payment disputes", () => {
  let disputeId: string;

  it("only the payer or the collector can dispute a payment marked as sent", async () => {
    const [payer, other] = payers;
    expect((await pay(payer!)).status).toBe(200);
    const c = await contributionOf(payer!);

    const byOther = await call(other!, "POST", `/contributions/${c.id}/dispute`, { reason: "Not my business", pin: PIN });
    expect(byOther.body.error.code).toBe("not_party");
    const byOutsider = await call("outsider", "POST", `/contributions/${c.id}/dispute`, { reason: "Hello", pin: PIN });
    expect(byOutsider.status).toBe(404);
    const wrongPin = await call(collector, "POST", `/contributions/${c.id}/dispute`, { reason: "Not here", pin: "9999" });
    expect(wrongPin.body.error.code).toBe("wrong_pin");
    await db.pool.query("select reset_pin_attempts($1)", [ids[collector]]);
  });

  it("the collector disputes a payment that hasn't arrived; it freezes until decided", async () => {
    const payer = payers[0]!;
    const c = await contributionOf(payer);
    const res = await call(collector, "POST", `/contributions/${c.id}/dispute`, { reason: "Nothing has reached my account.", pin: PIN });
    expect(res.status).toBe(201);
    disputeId = res.body.id;
    expect(res.body).toMatchObject({
      kind: "payment",
      status: "open",
      turn: 1,
      myRole: "collector",
      canVote: false,
      canSettle: true,
      payers: [{ id: ids[payer] }],
      payment: { amount: 5000, bankReference: `REF-${payer}` },
      votes: { payer: 0, collector: 0, eligible: 3, needed: 2, mine: null },
    });
    expect(res.body.timeline[0]).toMatchObject({ kind: "opened", message: "Nothing has reached my account." });

    expect((await contributionOf(payer)).status).toBe("disputed");
    const confirm = await call(collector, "POST", `/contributions/${c.id}/confirm`, { pin: PIN });
    expect(confirm.body.error.code).toBe("not_paid");
    expect((await call(collector, "POST", `/contributions/${c.id}/dispute`, { reason: "Again", pin: PIN })).body.error.code).toBe("disputed");
    expect((await call("ada", "GET", `/circles/${circleId}`)).body.openDisputes).toBe(1);
  });

  it("parties can't vote; the others can, and change their vote while it's open", async () => {
    const payer = payers[0]!;
    const voters = payers.slice(1);
    expect((await call(payer, "POST", `/disputes/${disputeId}/vote`, { side: "payer", pin: PIN })).body.error.code).toBe("party_cannot_vote");
    expect((await call(collector, "POST", `/disputes/${disputeId}/vote`, { side: "collector", pin: PIN })).body.error.code).toBe(
      "party_cannot_vote",
    );
    expect((await call("outsider", "GET", `/disputes/${disputeId}`)).status).toBe(404);

    const first = await call(voters[0]!, "POST", `/disputes/${disputeId}/vote`, { side: "collector", pin: PIN });
    expect(first.body).toMatchObject({ status: "open", myRole: "voter", canVote: true, votes: { collector: 1, mine: "collector" } });
    const changed = await call(voters[0]!, "POST", `/disputes/${disputeId}/vote`, { side: "payer", pin: PIN });
    expect(changed.body.votes).toMatchObject({ payer: 1, collector: 0, mine: "payer" });

    const comment = await call(payer, "POST", `/disputes/${disputeId}/comments`, { message: "I sent it from GTBank at 9am." });
    expect(comment.body.timeline.at(-1)).toMatchObject({ kind: "comment", actor: { id: ids[payer] } });
  });

  it("a majority of the eligible voters decides: the payment counts as confirmed", async () => {
    const payer = payers[0]!;
    const res = await call(payers[2]!, "POST", `/disputes/${disputeId}/vote`, { side: "payer", pin: PIN });
    expect(res.body).toMatchObject({ status: "resolved_for_payer", canVote: false, canSettle: false });
    expect(res.body.resolutionNote).toBe("Decided by the circle: 2 of 3 members voted that the money arrived.");
    expect((await contributionOf(payer)).status).toBe("fully_confirmed");
    expect((await call(payers[3]!, "POST", `/disputes/${disputeId}/vote`, { side: "collector", pin: PIN })).body.error.code).toBe(
      "dispute_closed",
    );
    expect((await call("ada", "GET", `/circles/${circleId}`)).body.openDisputes).toBe(0);

    const ledger = (await app.inject({ method: "GET", url: `/public/circles/${circleId}/ledger` })).json();
    const kinds = ledger.entries.map((e: { kind: string }) => e.kind);
    expect(kinds.filter((k: string) => k === "dispute_vote")).toHaveLength(3);
    const confirmed = ledger.entries.findLast((e: { kind: string }) => e.kind === "payment_confirmed");
    expect(JSON.parse(confirmed.body)).toMatchObject({ decidedBy: "dispute" });
  });

  it("the payer can settle by agreeing it didn't arrive, and then pay again", async () => {
    const payer = payers[1]!;
    await pay(payer);
    const c = await contributionOf(payer);
    const raised = await call(payer, "POST", `/contributions/${c.id}/dispute`, { reason: "Please confirm my payment.", pin: PIN });
    expect(raised.body).toMatchObject({ myRole: "payer", canSettle: true });

    const settled = await call(payer, "POST", `/disputes/${raised.body.id}/settle`, { pin: PIN });
    expect(settled.body.status).toBe("resolved_for_collector");
    expect(settled.body.resolutionNote).toContain("agreed the payment did not arrive");
    expect((await contributionOf(payer)).status).toBe("pending");
    expect((await pay(payer)).status).toBe(200);
    expect((await contributionOf(payer)).status).toBe("payer_confirmed");
  });

  it("a voter can't settle; the collector settles by confirming the money arrived", async () => {
    const payer = payers[1]!;
    const c = await contributionOf(payer);
    const raised = await call(collector, "POST", `/contributions/${c.id}/dispute`, { reason: "Still not here.", pin: PIN });
    expect((await call(payers[2]!, "POST", `/disputes/${raised.body.id}/settle`, { pin: PIN })).body.error.code).toBe("not_party");
    const settled = await call(collector, "POST", `/disputes/${raised.body.id}/settle`, { pin: PIN });
    expect(settled.body.status).toBe("resolved_for_payer");
    expect((await contributionOf(payer)).status).toBe("fully_confirmed");
  });

  it("lists the circle's disputes, newest first", async () => {
    const res = await call("ada", "GET", `/circles/${circleId}/disputes`);
    expect(res.body.disputes).toHaveLength(3);
    expect(res.body.disputes[2].id).toBe(disputeId);
    expect(res.body.disputes[0].timeline).toBeUndefined();
    expect((await call("outsider", "GET", `/circles/${circleId}/disputes`)).status).toBe(404);
  });
});

describe("shortfall disputes", () => {
  it("close by themselves once the missing payments are confirmed late", async () => {
    // Two of the four payers are confirmed; the payout is short by the other two.
    const res = await call(collector, "POST", `/circles/${circleId}/rounds/1/payout`, { amount: 10000, pin: PIN });
    expect(res.body.shortfall).toBe(10000);
    const shortfall = (await call(collector, "GET", `/disputes/${res.body.disputeId}`)).body;
    const missing = payers.slice(2);
    expect(shortfall).toMatchObject({ kind: "shortfall", status: "open", canVote: false, canSettle: true });
    expect(shortfall.payers.map((p: { id: string }) => nameOf(p.id)).sort()).toEqual([...missing].sort());
    expect((await call(payers[0]!, "POST", `/disputes/${shortfall.id}/vote`, { side: "payer", pin: PIN })).body.error.code).toBe(
      "no_vote",
    );

    // Late payments into turn 1, confirmed by the collector.
    for (const p of missing) {
      await pay(p);
      const { rows } = await db.pool.query<{ id: string }>(
        "select c.id from contributions c join rounds r on r.id = c.round_id where r.group_id = $1 and r.round_number = 1 and c.user_id = $2",
        [circleId, ids[p]],
      );
      await call(collector, "POST", `/contributions/${rows[0]!.id}/confirm`, { pin: PIN });
    }
    const after = (await call(collector, "GET", `/disputes/${shortfall.id}`)).body;
    expect(after.status).toBe("resolved_for_payer");
    expect(after.resolutionNote).toBe("Made up: every missing payment for this turn is now confirmed.");
    expect(after.payers).toEqual([]);
  });
});
