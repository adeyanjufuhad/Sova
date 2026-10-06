import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { freshDatabase } from "./setup/db.js";

const PIN = "2580";
const PEOPLE = {
  ada: { phone: "+2348000000041", name: "Ada Obi" },
  bayo: { phone: "+2348000000042", name: "Bayo Adeyemi" },
  chuka: { phone: "+2348000000043", name: "Chuka Eze" },
  dayo: { phone: "+2348000000044", name: "Dayo Ola" },
  efe: { phone: "+2348000000045", name: "Efe Udo" },
  funmi: { phone: "+2348000000046", name: "Funmi Bello" }, // outside the circle
} as const;
type Person = keyof typeof PEOPLE;
const CIRCLE: Person[] = ["ada", "bayo", "chuka", "dayo", "efe"];

let db: Awaited<ReturnType<typeof freshDatabase>>;
let app: FastifyInstance;
const tokens = {} as Record<Person, string>;
const ids = {} as Record<Person, string>;
let circleId: string;
/** Members by turn, turn 1 first (turn 1 is under way from the start). */
let byTurn: Person[];

let ip = 0;
const nextIp = () => `10.4.${Math.floor(++ip / 250)}.${ip % 250}`;
const nameOf = (id: string) => (Object.keys(ids) as Person[]).find((k) => ids[k] === id)!;

async function call(who: Person, method: "GET" | "POST" | "PATCH", url: string, payload?: object) {
  const res = await app.inject({ method, url, payload, remoteAddress: nextIp(), headers: { authorization: `Bearer ${tokens[who]}` } });
  return { status: res.statusCode, body: res.json() };
}
const detail = async (who: Person = "ada") => (await call(who, "GET", `/circles/${circleId}`)).body;
const turnOf = async (p: Person) => (await detail()).members.find((m: { id: string }) => m.id === ids[p])?.position;
const ledgerKinds = async () =>
  (await app.inject({ method: "GET", url: `/public/circles/${circleId}/ledger` })).json().entries.map((e: { kind: string }) => e.kind);

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
    name: "Market Friends", contributionAmount: 5000, memberCount: 5, cycleType: "weekly", startDate: tomorrow, pin: PIN,
  });
  circleId = created.body.id;
  for (const p of CIRCLE.slice(1)) {
    await call(p, "POST", "/circles/join", { code: created.body.inviteCode, voucherId: ids.ada, rulesVersion: 1, pin: PIN });
  }
  const members = (await detail()).members as { id: string; position: number }[];
  byTurn = [...members].sort((a, b) => a.position - b.position).map((m) => nameOf(m.id));
});
afterAll(async () => db.drop());

describe("swapping turns", () => {
  it("swaps two open turns once the other member accepts", async () => {
    const [, , third, fourth] = byTurn as [Person, Person, Person, Person];
    expect((await call(third, "POST", `/circles/${circleId}/swaps`, { targetId: ids[fourth], pin: "9999" })).body.error.code).toBe("wrong_pin");
    await db.pool.query("select reset_pin_attempts($1)", [ids[third]]);
    expect(
      (await call(third, "POST", `/circles/${circleId}/swaps`, { targetId: ids[byTurn[0]!], pin: PIN })).body.error.code,
    ).toBe("turn_started");

    const asked = await call(third, "POST", `/circles/${circleId}/swaps`, { targetId: ids[fourth], reason: "My rent is due early.", pin: PIN });
    expect(asked.status).toBe(201);
    const swap = asked.body.swaps[0];
    expect(swap).toMatchObject({ status: "pending", canCancel: true, canAnswer: false, requester: { turn: 3 }, target: { turn: 4 } });
    expect((await call(third, "POST", `/circles/${circleId}/swaps`, { targetId: ids[fourth], pin: PIN })).body.error.code).toBe("already_asked");

    const seen = (await call(fourth, "GET", `/circles/${circleId}/turn-changes`)).body.swaps[0];
    expect(seen).toMatchObject({ canAnswer: true, canCancel: false, reason: "My rent is due early." });
    const accepted = await call(fourth, "POST", `/swaps/${swap.id}/accept`, { pin: PIN });
    expect(accepted.body.swaps[0].status).toBe("accepted");
    expect(await turnOf(third)).toBe(4);
    expect(await turnOf(fourth)).toBe(3);
    expect(await ledgerKinds()).toContain("turns_swapped");

    // The draw is still checkable: the order as drawn is unchanged.
    const d = await detail();
    expect(d.draw.order.map((p: { id: string }) => nameOf(p.id))).toEqual(byTurn);
  });

  it("lets the other member decline and the asker cancel", async () => {
    const [, second, , fourth, fifth] = byTurn as [Person, Person, Person, Person, Person];
    const asked = (await call(fifth, "POST", `/circles/${circleId}/swaps`, { targetId: ids[second], pin: PIN })).body.swaps[0];
    expect((await call(fifth, "POST", `/swaps/${asked.id}/accept`, { pin: PIN })).body.error.code).toBe("not_target");
    expect((await call(second, "POST", `/swaps/${asked.id}/decline`)).body.swaps.find((s: { id: string }) => s.id === asked.id).status).toBe("declined");

    const again = (await call(fifth, "POST", `/circles/${circleId}/swaps`, { targetId: ids[fourth], pin: PIN })).body.swaps[0];
    expect((await call(fifth, "POST", `/swaps/${again.id}/cancel`)).body.swaps.find((s: { id: string }) => s.id === again.id).status).toBe("cancelled");
  });

  it("keeps an admin who pledged to collect last in last place", async () => {
    await db.pool.query("update groups set admin_collects_last = true where id = $1", [circleId]);
    const other = byTurn.find((p) => p !== "ada" && p !== byTurn[0])!;
    expect((await call(other, "POST", `/circles/${circleId}/swaps`, { targetId: ids.ada, pin: PIN })).body.error.code).toBe("pledged_last");
    await db.pool.query("update groups set admin_collects_last = false where id = $1", [circleId]);
  });
});

describe("handing over a place", () => {
  let leaving: Person;
  let handoverId: string;

  it("refuses the admin, unknown numbers and people already in the circle", async () => {
    leaving = byTurn.slice(1).find((p) => p !== "ada")!;
    expect((await call("ada", "POST", `/circles/${circleId}/handovers`, { phone: PEOPLE.funmi.phone, pin: PIN })).body.error.code).toBe(
      "admin_cannot_leave",
    );
    expect((await call(leaving, "POST", `/circles/${circleId}/handovers`, { phone: "08099999999", pin: PIN })).body.error.code).toBe(
      "no_account",
    );
    expect((await call(leaving, "POST", `/circles/${circleId}/handovers`, { phone: PEOPLE.ada.phone, pin: PIN })).body.error.code).toBe(
      "already_member",
    );
  });

  it("needs the replacement to accept the rules, then the admin to approve", async () => {
    const made = await call(leaving, "POST", `/circles/${circleId}/handovers`, { phone: "0800 000 0046", reason: "Moving to Abuja.", pin: PIN });
    expect(made.status).toBe(201);
    handoverId = made.body.handovers[0].id;
    expect(made.body.handovers[0]).toMatchObject({ status: "pending", canCancel: true, replacement: { name: "Funmi Bello" } });

    const offer = (await call("funmi", "GET", "/me/handover-offers")).body.offers[0];
    expect(offer).toMatchObject({ id: handoverId, reason: "Moving to Abuja.", circle: { name: "Market Friends", payoutAmount: 20000 } });
    expect(offer.turn).toBe(await turnOf(leaving));

    expect((await call("ada", "POST", `/handovers/${handoverId}/approve`, { pin: PIN })).body.error.code).toBe("not_ready");
    expect((await call("funmi", "POST", `/handovers/${handoverId}/accept`, { rulesVersion: 2, pin: PIN })).body.error.code).toBe("rules_changed");
    expect((await call("funmi", "POST", `/handovers/${handoverId}/accept`, { rulesVersion: 1, pin: PIN })).body.offers).toEqual([]);
    expect((await call(leaving, "POST", `/handovers/${handoverId}/approve`, { pin: PIN })).body.error.code).toBe("not_admin");

    const approved = await call("ada", "POST", `/handovers/${handoverId}/approve`, { pin: PIN });
    expect(approved.body.handovers[0].status).toBe("approved");
    // Nothing moves until the current turn ends.
    expect(await turnOf(leaving)).toBeDefined();
    expect((await call("funmi", "GET", `/circles/${circleId}`)).status).toBe(404);
  });

  it("takes effect when the turn ends, keeps the turn, and goes on the record", async () => {
    const turn = await turnOf(leaving);
    const collector = byTurn[0]!;
    // A pending swap with turn 2's member is cancelled once their turn starts (or once they leave).
    const turn2 = (await detail()).members.find((m: { position: number }) => m.position === 2).id as string;
    const asker = byTurn.find((p) => p !== nameOf(turn2) && p !== collector && p !== leaving && p !== "ada")!;
    const pending = (await call(asker, "POST", `/circles/${circleId}/swaps`, { targetId: turn2, pin: PIN })).body.swaps[0];

    const closed = await call(collector, "POST", `/circles/${circleId}/rounds/1/payout`, { amount: 0, pin: PIN });
    expect(closed.body.nextRound).toBe(2);

    const now = await call("funmi", "GET", `/circles/${circleId}`);
    expect(now.status).toBe(200);
    expect(now.body.members.find((m: { id: string }) => m.id === ids.funmi)).toMatchObject({ position: turn, acceptedRules: true });
    expect((await call(leaving, "GET", `/circles/${circleId}`)).status).toBe(404);

    const changes = (await call("ada", "GET", `/circles/${circleId}/turn-changes`)).body;
    expect(changes.handovers.find((h: { id: string }) => h.id === handoverId).status).toBe("completed");
    expect(changes.swaps.find((s: { id: string }) => s.id === pending.id).status).toBe("cancelled");
    const kinds = await ledgerKinds();
    expect(kinds).toContain("slot_handed_over");
    expect(kinds.lastIndexOf("member_joined")).toBeGreaterThan(kinds.indexOf("draw_revealed"));
  });
});
