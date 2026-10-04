import type pg from "pg";

import { hashPin } from "../auth/pin.js";
import { commitmentOf, drawOrder, newSeed } from "../lib/draw.js";

/**
 * Realistic demo data so the product looks alive for the demo and judges.
 * Every seeded person uses the reserved range +2348000000xxx; re-running the
 * seed deletes and recreates only those people and their circles.
 *
 * Circles, from the demo member's point of view:
 *  1. Office Esusu          weekly, mid-cycle; you still owe this turn
 *  2. Unilag Class of '24   monthly; you are admin and collecting; Emeka awaits confirmation
 *  3. Ikeja Tech Hub Esusu  new; 4 of 8 joined; join with code T7KP9Q (turns not drawn yet)
 *  4. Church Adashe         completed; builds your history
 *  5. Yaba Traders Circle   payout shortfall -> open dispute; Musa collected then stopped paying
 *
 * Draws: the forming circle gets a fresh secret seed, like any new circle. The
 * circles that already started need a scripted payout order for the story, so
 * the seed script searches for a seed whose draw produces that order. Their
 * draws still verify (commitment and order); real circles never do this.
 */

export const DEMO_PHONE = "+2348000000000";
export const DEMO_PIN = "2580";
const SEEDED_PHONES = "+2348000000%";

type Ctx = { client: pg.PoolClient; users: Map<string, string> };

const day = (offset: number) => {
  const d = new Date();
  d.setUTCHours(0, 0, 0, 0);
  d.setUTCDate(d.getUTCDate() + offset);
  return d;
};
const iso = (d: Date) => d.toISOString().slice(0, 10);

const PEOPLE: [key: string, name: string, bank?: [string, string]][] = [
  ["ada", "Ada Obi", ["OPay", "9061234567"]],
  ["ifeoma", "Ifeoma Okeke", ["Access Bank", "0123456789"]],
  ["bayo", "Bayo Adeyemi", ["Guaranty Trust Bank (GTBank)", "0234567891"]],
  ["halima", "Halima Sani", ["Moniepoint Microfinance Bank", "8012345678"]],
  ["chuka", "Chuka Obi", ["Zenith Bank", "2012345678"]],
  ["zainab", "Zainab Bello", ["Kuda Microfinance Bank", "2034567812"]],
  ["tolu", "Tolu Ajayi", ["Wema Bank", "0345678912"]],
  ["emeka", "Emeka Nwosu", ["First Bank of Nigeria", "3012345678"]],
  ["amina", "Amina Yusuf", ["PalmPay", "8123456789"]],
  ["david", "David Etim", ["United Bank for Africa (UBA)", "2045678123"]],
  ["kemi", "Kemi Adebayo", ["Sterling Bank", "0456789123"]],
  ["femi", "Femi Lawal", ["Fidelity Bank", "6012345678"]],
  ["ngozi", "Ngozi Eze", ["Polaris Bank", "1012345678"]],
  ["sani", "Sani Musa", ["Jaiz Bank", "0012345678"]],
  ["grace", "Grace Okon", ["Union Bank of Nigeria", "0567891234"]],
  ["peter", "Peter Ade", ["Ecobank Nigeria", "4012345678"]],
  ["musa", "Musa Kabir", ["Keystone Bank", "6023456789"]],
  ["blessing", "Blessing Uche", ["Providus Bank", "1302345678"]],
];

async function addUsers(ctx: Ctx) {
  const pinHash = await hashPin(DEMO_PIN);
  for (const [i, [key, name, bank]] of PEOPLE.entries()) {
    const phone = `+2348000000${String(i).padStart(3, "0")}`;
    const { rows } = await ctx.client.query<{ id: string }>(
      `insert into users (phone, full_name, pin_hash, bank_name, account_number, account_name, is_demo)
       values ($1, $2, $3, $4, $5, $2, $6) returning id`,
      [phone, name, pinHash, bank?.[0] ?? null, bank?.[1] ?? null, key === "ada"],
    );
    ctx.users.set(key, rows[0]!.id);
  }
}

const id = (ctx: Ctx, key: string) => {
  const v = ctx.users.get(key);
  if (!v) throw new Error(`unknown seeded person ${key}`);
  return v;
};

interface CircleSpec {
  name: string;
  admin: string;
  amount: number;
  cycle: "daily" | "weekly" | "monthly";
  start: number;
  code: string;
  size: number;
  /** In payout order; null position means "not drawn yet". */
  members: { key: string; position: number | null; vouchedBy?: string }[];
  rules: { lateFee: number; graceDays: number; earlyExit: string; emergency?: string };
  status: "forming" | "active" | "completed";
  adminCollectsLast?: boolean;
}

/** A seed whose draw reproduces the scripted order (see the note at the top). */
function seedForOrder(order: string[], adminId: string, adminCollectsLast: boolean): string {
  for (let attempt = 0; attempt < 1_000_000; attempt++) {
    const seed = newSeed();
    const drawn = drawOrder(seed, order, adminId, adminCollectsLast);
    if (drawn.every((id, i) => id === order[i])) return seed;
  }
  throw new Error("no seed found for the scripted order");
}

const HOUR = 3_600_000;
const at = (d: Date, hours: number) => new Date(d.getTime() + hours * HOUR);

/**
 * Timestamps follow a real circle's life so the ledger reads in order:
 * created three days before the start (two days ago at most for new circles),
 * members join over the following hours, the draw is revealed two days before
 * the start, and each turn opens when the previous payout is confirmed.
 */
async function addCircle(ctx: Ctx, c: CircleSpec): Promise<string> {
  const createdAt = at(day(Math.min(c.start - 3, -2)), 9);
  const { rows } = await ctx.client.query<{ id: string }>(
    `insert into groups (name, admin_id, member_count, contribution_amount, cycle_type, start_date, invite_code, status,
                         admin_collects_last, created_at)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) returning id`,
    [c.name, id(ctx, c.admin), c.size, c.amount, c.cycle, iso(day(c.start)), c.code, c.status, c.adminCollectsLast ?? false, createdAt],
  );
  const groupId = rows[0]!.id;

  // Like a real circle: the draw is committed before members join and revealed once it's full.
  const drawn = c.members.every((m) => m.position !== null);
  const order = [...c.members].sort((a, b) => (a.position ?? 0) - (b.position ?? 0)).map((m) => id(ctx, m.key));
  const seed = drawn ? seedForOrder(order, id(ctx, c.admin), c.adminCollectsLast ?? false) : newSeed();
  await ctx.client.query("insert into circle_draws (group_id, commitment, seed, created_at) values ($1, $2, $3, $4)", [
    groupId,
    commitmentOf(seed),
    seed,
    createdAt,
  ]);
  const rules = await ctx.client.query<{ id: string }>(
    `insert into group_rules (group_id, version, late_fee, grace_days, early_exit_policy, emergency_policy, created_by, created_at)
     values ($1, 1, $2, $3, $4, $5, $6, $7) returning id`,
    [groupId, c.rules.lateFee, c.rules.graceDays, c.rules.earlyExit, c.rules.emergency ?? null, id(ctx, c.admin), createdAt],
  );

  for (const [i, m] of c.members.entries()) {
    const joinedAt = at(createdAt, i);
    await ctx.client.query(
      "insert into group_members (group_id, user_id, payout_position, joined_at) values ($1, $2, $3, $4)",
      [groupId, id(ctx, m.key), m.position, joinedAt],
    );
    if (m.vouchedBy) {
      await ctx.client.query("insert into vouches (group_id, voucher_id, vouchee_id, created_at) values ($1, $2, $3, $4)", [
        groupId,
        id(ctx, m.vouchedBy),
        id(ctx, m.key),
        joinedAt,
      ]);
    }
    await ctx.client.query("insert into rule_acceptances (rules_id, user_id, accepted_at) values ($1, $2, $3)", [
      rules.rows[0]!.id,
      id(ctx, m.key),
      joinedAt,
    ]);
  }

  if (drawn) {
    await ctx.client.query("update circle_draws set revealed_at = $2 where group_id = $1", [groupId, revealAt(c)]);
  }
  return groupId;
}

const revealAt = (c: CircleSpec) => at(day(c.start - 2), 9);

const STEP = { daily: 1, weekly: 7, monthly: 30 } as const;

/**
 * Creates rounds 1..upTo for a circle. Completed rounds have every other member
 * fully confirmed and the payout confirmed in full, unless `gaps` says otherwise.
 */
async function addRounds(
  ctx: Ctx,
  groupId: string,
  spec: CircleSpec,
  upTo: number,
  opts: {
    activeLast?: boolean;
    /** round number -> member key -> status for that member (default fully_confirmed) */
    overrides?: Record<number, Record<string, "pending" | "payer_confirmed" | "fully_confirmed" | "missing">>;
    shortPayout?: Record<number, number>;
    /** Runs right after turn n's payout is confirmed (e.g. the automatic dispute). */
    afterPayout?: Record<number, (roundId: string, at: Date) => Promise<void>>;
  } = {},
): Promise<Map<number, string>> {
  const ordered = [...spec.members].sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
  const roundIds = new Map<number, string>();
  for (let n = 1; n <= upTo; n++) {
    const collector = ordered[n - 1]!;
    const due = day(spec.start + (n - 1) * STEP[spec.cycle]);
    const active = opts.activeLast && n === upTo;
    // Turn 1 opens just after the draw; later turns open when the previous payout is confirmed.
    const openedAt = n === 1 ? at(revealAt(spec), 1) : at(day(spec.start + (n - 2) * STEP[spec.cycle]), 18);
    const { rows } = await ctx.client.query<{ id: string }>(
      `insert into rounds (group_id, round_number, collector_id, due_date, status, created_at)
       values ($1, $2, $3, $4, $5, $6) returning id`,
      [groupId, n, id(ctx, collector.key), iso(due), active ? "active" : "completed", openedAt],
    );
    const roundId = rows[0]!.id;
    roundIds.set(n, roundId);

    let received = 0;
    for (const m of ordered) {
      if (m.key === collector.key) continue;
      const status = opts.overrides?.[n]?.[m.key] ?? (active ? "pending" : "fully_confirmed");
      if (status === "pending" || status === "missing") continue;
      // Payments land three hours apart, each confirmed an hour later, so the record reads in order.
      const paidAt = at(due, -24 + 3 * ordered.indexOf(m));
      await ctx.client.query(
        `insert into contributions
           (round_id, group_id, user_id, amount, payer_confirmed, payer_confirmed_at,
            collector_confirmed, collector_confirmed_at, status, bank_reference)
         values ($1, $2, $3, $4, true, $5, $6, $7, $8, $9)`,
        [
          roundId,
          groupId,
          id(ctx, m.key),
          spec.amount,
          paidAt,
          status === "fully_confirmed",
          status === "fully_confirmed" ? at(paidAt, 1) : null,
          status,
          `FT${String(Math.abs(hash(`${roundId}${m.key}`))).slice(0, 10)}`,
        ],
      );
      if (status === "fully_confirmed") received += spec.amount;
    }
    if (!active) {
      const amount = opts.shortPayout?.[n] ?? received;
      const confirmedAt = at(due, 17);
      await ctx.client.query("update rounds set payout_received = $2, payout_confirmed_at = $3 where id = $1", [
        roundId,
        amount,
        confirmedAt,
      ]);
      await opts.afterPayout?.[n]?.(roundId, confirmedAt);
    }
  }
  return roundIds;
}

function hash(s: string): number {
  let h = 0;
  for (const ch of s) h = (h * 31 + ch.charCodeAt(0)) | 0;
  return h;
}

/** Deletes previous demo data and recreates it. Runs in one transaction. */
export async function seedDemo(pool: pg.Pool): Promise<{ circles: number; people: number }> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    // Demo ledgers can only be purged with this flag, and only for circles run by
    // the reserved demo numbers (see ledger_guard). Real circles' ledgers stay.
    await client.query("set local sova.purge_demo = 'on'");
    await client.query(
      `delete from ledger_entries where group_id in
         (select g.id from groups g join users u on u.id = g.admin_id where u.phone like $1)`,
      [SEEDED_PHONES],
    );
    // Circles run by seeded people go next (cascades to members, rounds, contributions, rules...).
    await client.query(
      `delete from groups where admin_id in (select id from users where phone like $1)`,
      [SEEDED_PHONES],
    );
    await client.query("delete from users where phone like $1", [SEEDED_PHONES]);

    const ctx: Ctx = { client, users: new Map() };
    await addUsers(ctx);

    // 1. Office Esusu: weekly, turn 3 active, Ada still owes Halima.
    const office: CircleSpec = {
      name: "Office Esusu",
      admin: "ifeoma",
      amount: 20000,
      cycle: "weekly",
      start: -12,
      code: "K7QX2M",
      size: 6,
      members: [
        { key: "ifeoma", position: 1 },
        { key: "bayo", position: 2 },
        { key: "halima", position: 3 },
        { key: "ada", position: 4 },
        { key: "chuka", position: 5 },
        { key: "zainab", position: 6, vouchedBy: "ifeoma" },
      ],
      rules: {
        lateFee: 1000,
        graceDays: 1,
        earlyExit: "find_replacement",
        emergency: "If a member falls ill, the group can agree to move their turn earlier.",
      },
      status: "active",
    };
    const officeId = await addCircle(ctx, office);
    await addRounds(ctx, officeId, office, 3, {
      activeLast: true,
      overrides: { 3: { ifeoma: "fully_confirmed", bayo: "fully_confirmed", chuka: "payer_confirmed" } },
    });

    // 2. Unilag Class of '24 Ajo: Ada is admin and collecting turn 2.
    const unilag: CircleSpec = {
      name: "Unilag Class of '24 Ajo",
      admin: "ada",
      amount: 10000,
      cycle: "monthly",
      start: -21,
      code: "P4DN8R",
      size: 5,
      members: [
        { key: "tolu", position: 1 },
        { key: "ada", position: 2 },
        { key: "emeka", position: 3 },
        { key: "amina", position: 4 },
        { key: "david", position: 5, vouchedBy: "tolu" },
      ],
      rules: { lateFee: 500, graceDays: 2, earlyExit: "refund_after_cycle" },
      status: "active",
    };
    const unilagId = await addCircle(ctx, unilag);
    await addRounds(ctx, unilagId, unilag, 2, {
      activeLast: true,
      overrides: { 2: { tolu: "fully_confirmed", emeka: "payer_confirmed" } },
    });

    // 3. Ikeja Tech Hub Esusu: new, 4 of 8 joined, turns not drawn. Ada can join with T7KP9Q.
    const techHub: CircleSpec = {
      name: "Ikeja Tech Hub Esusu",
      admin: "kemi",
      amount: 15000,
      cycle: "weekly",
      start: 10,
      code: "T7KP9Q",
      size: 8,
      members: [
        { key: "kemi", position: null },
        { key: "femi", position: null },
        { key: "ngozi", position: null },
        { key: "sani", position: null, vouchedBy: "kemi" },
      ],
      rules: {
        lateFee: 1000,
        graceDays: 1,
        earlyExit: "find_replacement",
        emergency: "Members can swap turns for emergencies if both agree.",
      },
      status: "forming",
      adminCollectsLast: true,
    };
    await addCircle(ctx, techHub);

    // 4. Church Adashe: completed four-person circle.
    const church: CircleSpec = {
      name: "Church Adashe",
      admin: "grace",
      amount: 5000,
      cycle: "weekly",
      start: -60,
      code: "CHRDA9",
      size: 4,
      members: [
        { key: "grace", position: 1 },
        { key: "ada", position: 2 },
        { key: "peter", position: 3 },
        { key: "blessing", position: 4 },
      ],
      rules: { lateFee: 0, graceDays: 2, earlyExit: "forfeit_fee" },
      status: "completed",
    };
    const churchId = await addCircle(ctx, church);
    await addRounds(ctx, churchId, church, 4);

    // 5. Yaba Traders Circle: Musa collected turn 1 then missed turn 2; Peter's payout came up short.
    const yaba: CircleSpec = {
      name: "Yaba Traders Circle",
      admin: "peter",
      amount: 10000,
      cycle: "weekly",
      start: -16,
      code: "YBTR4K",
      size: 4,
      members: [
        { key: "musa", position: 1 },
        { key: "peter", position: 2 },
        { key: "ada", position: 3 },
        { key: "sani", position: 4 },
      ],
      rules: { lateFee: 1000, graceDays: 1, earlyExit: "find_replacement" },
      status: "active",
    };
    const yabaId = await addCircle(ctx, yaba);
    await addRounds(ctx, yabaId, yaba, 3, {
      activeLast: true,
      overrides: { 2: { musa: "missing" }, 3: { musa: "missing", peter: "fully_confirmed", sani: "fully_confirmed" } },
      shortPayout: { 2: 20000 },
      // The short payout opens a dispute straight away, as it does in the app.
      afterPayout: {
        2: async (roundId, confirmedAt) => {
          const dispute = await client.query<{ id: string }>(
            `insert into disputes (group_id, round_id, raised_by, against_user_id, reason, created_at)
             values ($1, $2, $3, $4, $5, $6) returning id`,
            [
              yabaId,
              roundId,
              id(ctx, "peter"),
              id(ctx, "musa"),
              "My turn-2 payout was ₦10,000 short. Musa collected turn 1 and has not paid since.",
              confirmedAt,
            ],
          );
          for (const [actor, kind, message, hours] of [
            ["peter", "opened", "Opened after confirming a ₦20,000 payout instead of ₦30,000.", 0],
            ["ada", "evidence", "My transfer receipt for turn 2 is attached to my contribution.", 20],
            ["musa", "comment", "I will pay this week. My shop was closed.", 44],
          ] as const) {
            await client.query(
              "insert into dispute_events (dispute_id, actor_id, kind, message, created_at) values ($1, $2, $3, $4, $5)",
              [dispute.rows[0]!.id, id(ctx, actor), kind, message, at(confirmedAt, hours)],
            );
          }
        },
      },
    });

    // Sova Scores from the database function, for everyone seeded.
    for (const userId of ctx.users.values()) {
      await client.query("select calculate_sova_score($1)", [userId]);
    }

    await client.query("commit");
    return { circles: 5, people: PEOPLE.length };
  } catch (err) {
    await client.query("rollback");
    throw err;
  } finally {
    client.release();
  }
}
