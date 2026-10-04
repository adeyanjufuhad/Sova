import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { commitmentOf, drawOrder } from "../src/lib/draw.js";
import { firstBrokenEntry, type ChainEntry } from "../src/lib/ledger.js";
import { seedDemo } from "../src/seed/demo.js";
import { freshDatabase } from "./setup/db.js";

let db: Awaited<ReturnType<typeof freshDatabase>>;
let app: FastifyInstance;

beforeAll(async () => {
  db = await freshDatabase();
  await seedDemo(db.pool);
  app = await buildApp(
    loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent", JWT_SECRET: "test-secret-that-is-at-least-32-characters-long" }),
    db.pool,
  );
});
afterAll(async () => db.drop());

const circleId = async (code: string) =>
  (await db.pool.query<{ id: string }>("select id from groups where invite_code = $1", [code])).rows[0]!.id;

async function ledger(code: string) {
  const res = await app.inject({ method: "GET", url: `/public/circles/${await circleId(code)}/ledger` });
  expect(res.statusCode).toBe(200);
  return res.json() as { circle: { name: string }; head: { seq: number; hash: string }; entries: ChainEntry[] };
}

const bodies = (entries: ChainEntry[], kind: string) =>
  entries.filter((e) => e.kind === kind).map((e) => JSON.parse(e.body) as Record<string, unknown>);

describe("ledger", () => {
  it("records each circle's history as a hash chain anyone can recompute", async () => {
    for (const code of ["K7QX2M", "P4DN8R", "T7KP9Q", "CHRDA9", "YBTR4K"]) {
      const { entries, head } = await ledger(code);
      expect(firstBrokenEntry(entries)).toBeNull();
      expect(head.hash).toBe(entries[entries.length - 1]!.hash);
      expect(entries[0]!.kind).toBe("circle_created");
    }
  });

  it("lets anyone check the fair draw from the chain alone", async () => {
    const { entries } = await ledger("K7QX2M");
    const [created] = bodies(entries, "circle_created");
    const [committed] = bodies(entries, "draw_committed");
    const [revealed] = bodies(entries, "draw_revealed");
    const seed = revealed!.seed as string;
    const order = (revealed!.order as { id: string }[]).map((m) => m.id);

    expect(commitmentOf(seed)).toBe(committed!.commitment);
    const admin = (created!.admin as { id: string }).id;
    expect(drawOrder(seed, [...order].reverse(), admin, created!.adminCollectsLast as boolean)).toEqual(order);
    // The commitment was recorded before anyone but the admin joined, and before the reveal.
    const committedAt = entries.findIndex((e) => e.kind === "draw_committed");
    const joins = entries.flatMap((e, i) => (e.kind === "member_joined" ? [i] : []));
    expect(joins.every((i) => i > committedAt)).toBe(true);
    expect(committedAt).toBeLessThan(entries.findIndex((e) => e.kind === "draw_revealed"));
  });

  it("records payments, payouts and the automatic dispute", async () => {
    const { entries } = await ledger("YBTR4K");
    const payouts = bodies(entries, "payout_confirmed");
    expect(payouts.map((p) => p.shortfall)).toEqual([0, 10000]);
    expect(bodies(entries, "dispute_opened")).toHaveLength(1);
    expect(bodies(entries, "payment_confirmed").length).toBeGreaterThan(0);
  });

  it("never exposes phone numbers or bank details", async () => {
    const { entries } = await ledger("K7QX2M");
    const all = entries.map((e) => e.body).join("\n");
    expect(all).not.toMatch(/\+234|\b\d{10}\b/);
    expect(bodies(entries, "member_joined")[0]!.member).toMatchObject({ name: "Ifeoma O." });
  });

  it("refuses to change or remove entries, even for the database owner", async () => {
    const id = await circleId("K7QX2M");
    await expect(db.pool.query("update ledger_entries set body = '{}' where group_id = $1 and seq = 1", [id])).rejects.toThrow(
      /append-only/,
    );
    await expect(db.pool.query("delete from ledger_entries where group_id = $1", [id])).rejects.toThrow(/append-only/);
    await expect(db.pool.query("truncate ledger_entries")).rejects.toThrow(/append-only/);
    // Nor can the circle itself be deleted while it has a ledger.
    await expect(db.pool.query("delete from groups where id = $1", [id])).rejects.toThrow(/foreign key/);
  });

  it("detects a single altered entry", async () => {
    const { entries } = await ledger("CHRDA9");
    const tampered = entries.map((e) => (e.seq === 5 ? { ...e, body: e.body.replace(/\d+/, "1") } : e));
    expect(firstBrokenEntry(tampered)).toBe(5);
  });

  it("answers 404 for unknown circles", async () => {
    const res = await app.inject({ method: "GET", url: "/public/circles/00000000-0000-0000-0000-000000000000/ledger" });
    expect(res.statusCode).toBe(404);
  });
});
