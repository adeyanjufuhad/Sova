import { randomUUID } from "node:crypto";

import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";

import { requireUser, userIdOf } from "../auth/plugin.js";
import { verifyPin } from "../auth/pin.js";
import type { TokenService } from "../auth/tokens.js";
import { inTransaction } from "../db.js";
import { commitmentOf, newInviteCode, newSeed } from "../lib/draw.js";
import { AppError, notFound } from "../lib/errors.js";
import type { ProofStorage } from "../lib/storage.js";

/** Today's date in Nigeria, as YYYY-MM-DD. */
const todayInLagos = () => new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Lagos" }).format(new Date());

const pin = z.string().regex(/^\d{4}$/, "Your PIN is 4 digits.");
const uuid = z.uuid("Not a valid id.");
const naira = (max: number) => z.number().int("Use whole naira.").min(0).max(max);

const createBody = z.object({
  name: z.string().trim().min(2, "Give the circle a name.").max(60, "Keep the name under 60 characters."),
  contributionAmount: naira(10_000_000).min(100, "The contribution must be at least ₦100."),
  memberCount: z.number().int().min(2, "A circle needs at least 2 people.").max(30, "A circle can have up to 30 people."),
  cycleType: z.enum(["daily", "weekly", "monthly"]),
  startDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Use a date like 2026-10-20.")
    .refine((d) => d >= todayInLagos(), "The first payment can't be in the past."),
  adminCollectsLast: z.boolean().default(false),
  rules: z
    .object({
      lateFee: naira(1_000_000).default(0),
      graceDays: z.number().int().min(0).max(30).default(0),
      earlyExitPolicy: z.enum(["find_replacement", "refund_after_cycle", "forfeit_fee"]).default("find_replacement"),
      emergencyPolicy: z.string().trim().max(1000).nullish(),
      otherRules: z.string().trim().max(2000).nullish(),
    })
    .default({ lateFee: 0, graceDays: 0, earlyExitPolicy: "find_replacement" }),
  pin,
});

const codeParam = z.object({
  code: z
    .string()
    .transform((c) => c.toUpperCase().replace(/[\s-]/g, ""))
    .pipe(z.string().regex(/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$/, "Invite codes are 6 letters and numbers.")),
});
const joinBody = codeParam.extend({ voucherId: uuid.nullish(), rulesVersion: z.number().int().positive(), pin });
const idParam = z.object({ id: uuid });
const roundParam = z.object({ id: uuid, number: z.coerce.number().int().positive() });
const acceptBody = z.object({ version: z.number().int().positive() });
const payBody = z.object({
  bankReference: z.string().trim().min(1).max(60).nullish(),
  /** Key returned by the proof upload endpoint, once the photo is uploaded. */
  proofKey: z.string().max(200).nullish(),
  pin,
});
const PROOF_TYPES = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" } as const;
const proofBody = z.object({
  contentType: z.enum(Object.keys(PROOF_TYPES) as [keyof typeof PROOF_TYPES], { error: "Upload a JPEG, PNG or WebP photo." }),
  size: z.number().int().min(1).max(5 * 1024 * 1024, "Photos can be up to 5 MB."),
});
const pinBody = z.object({ pin });
const payoutBody = z.object({ amount: naira(1_000_000_000), pin });

type Status = "forming" | "active" | "paused" | "completed";

interface CircleRow {
  id: string;
  name: string;
  status: Status;
  contribution_amount: number;
  cycle_type: string;
  member_count: number;
  start_date: string;
  invite_code: string;
  admin_id: string;
  admin_collects_last: boolean;
  joined: number;
}

const CIRCLE_COLUMNS = `g.id, g.name, g.status, g.contribution_amount, g.cycle_type, g.member_count,
  g.start_date::text, g.invite_code, g.admin_id, g.admin_collects_last,
  (select count(*)::int from group_members x where x.group_id = g.id) as joined`;

const circleSummary = (g: CircleRow) => ({
  id: g.id,
  name: g.name,
  status: g.status,
  contributionAmount: g.contribution_amount,
  /** What each collector receives: one contribution from every other member. */
  payoutAmount: g.contribution_amount * (g.member_count - 1),
  cycleType: g.cycle_type,
  memberCount: g.member_count,
  membersJoined: g.joined,
  startDate: g.start_date,
  inviteCode: g.invite_code,
  adminId: g.admin_id,
  adminCollectsLast: g.admin_collects_last,
});

const rulesView = (r: {
  version: number;
  late_fee: number;
  grace_days: number;
  early_exit_policy: string;
  emergency_policy: string | null;
  other_rules: string | null;
}) => ({
  version: r.version,
  lateFee: r.late_fee,
  graceDays: r.grace_days,
  earlyExitPolicy: r.early_exit_policy,
  emergencyPolicy: r.emergency_policy,
  otherRules: r.other_rules,
});

const RULES_COLUMNS = "id, version, late_fee, grace_days, early_exit_policy, emergency_policy, other_rules";

/** Moderate per-IP limit: stops guessing invite codes and PINs by brute force. */
const limited = { rateLimit: { max: 30, timeWindow: "1 minute" } };

export async function circleRoutes(
  app: FastifyInstance,
  opts: { pool: pg.Pool; tokens: TokenService; storage: ProofStorage | null },
) {
  const { pool, storage } = opts;

  const requireStorage = () => {
    if (!storage) throw new AppError(503, "uploads_not_configured", "Photo uploads aren't set up yet. Add the bank reference instead.");
    return storage;
  };
  /** Proof photos live under proofs/<circle>/<turn>/<payer>/; a member can only attach their own. */
  const proofPrefix = (circleId: string, number: number, userId: string) => `proofs/${circleId}/${number}/${userId}/`;
  app.addHook("preHandler", requireUser(opts.tokens));

  /** Everyone in a circle needs a name (others must recognise them) and a PIN. */
  const requireProfile = async (userId: string) => {
    const { rows } = await pool.query<{ full_name: string | null }>("select full_name from users where id = $1", [userId]);
    if (!rows[0]?.full_name) throw new AppError(409, "profile_incomplete", "Add your name before joining a circle.");
  };

  /** Loads a circle the user belongs to; anyone else gets 404 so ids reveal nothing. */
  const loadCircle = async (circleId: string, userId: string) => {
    const { rows } = await pool.query<CircleRow & { my_position: number | null }>(
      `select ${CIRCLE_COLUMNS}, m.payout_position as my_position
         from groups g join group_members m on m.group_id = g.id and m.user_id = $2
        where g.id = $1`,
      [circleId, userId],
    );
    if (!rows[0]) throw notFound("Circle");
    return rows[0];
  };

  const roundId = async (circleId: string, number: number) => {
    const { rows } = await pool.query<{ id: string }>("select id from rounds where group_id = $1 and round_number = $2", [
      circleId,
      number,
    ]);
    if (!rows[0]) throw notFound("Turn");
    return rows[0].id;
  };

  app.get("/circles", async (req) => {
    const me = userIdOf(req);
    const { rows } = await pool.query<
      CircleRow & {
        my_position: number | null;
        round_number: number | null;
        due_date: string | null;
        collector_id: string | null;
        collector_name: string | null;
        paid: number;
        confirmed: number;
        my_status: string | null;
      }
    >(
      `select ${CIRCLE_COLUMNS}, m.payout_position as my_position,
              r.round_number, r.due_date::text, r.collector_id, cu.full_name as collector_name,
              (select count(*)::int from contributions c where c.round_id = r.id and c.status in ('payer_confirmed', 'fully_confirmed')) as paid,
              (select count(*)::int from contributions c where c.round_id = r.id and c.status = 'fully_confirmed') as confirmed,
              (select c.status from contributions c where c.round_id = r.id and c.user_id = $1) as my_status
         from group_members m
         join groups g on g.id = m.group_id
         left join rounds r on r.group_id = g.id and r.status = 'active'
         left join users cu on cu.id = r.collector_id
        where m.user_id = $1
        order by case g.status when 'active' then 0 when 'forming' then 1 when 'paused' then 2 else 3 end, g.created_at desc`,
      [me],
    );
    return {
      circles: rows.map((g) => ({
        ...circleSummary(g),
        myPosition: g.my_position,
        currentRound:
          g.round_number === null
            ? null
            : {
                number: g.round_number,
                dueDate: g.due_date,
                collector: { id: g.collector_id, name: g.collector_name },
                isMyTurn: g.collector_id === me,
                paidCount: g.paid,
                confirmedCount: g.confirmed,
                expectedCount: g.member_count - 1,
                myContribution: g.collector_id === me ? null : (g.my_status ?? "unpaid"),
              },
      })),
    };
  });

  app.post("/circles", { config: limited }, async (req, reply) => {
    const me = userIdOf(req);
    const body = createBody.parse(req.body);
    await requireProfile(me);
    await verifyPin(pool, me, body.pin);

    const seed = newSeed();
    const circleId = await inTransaction(pool, async (client) => {
      // Codes are random; on the rare clash, try a new one.
      for (let attempt = 0; ; attempt++) {
        await client.query("savepoint new_code");
        try {
          const { rows } = await client.query<{ id: string }>(
            `insert into groups (name, admin_id, member_count, contribution_amount, cycle_type, start_date, invite_code, admin_collects_last)
             values ($1, $2, $3, $4, $5, $6, $7, $8) returning id`,
            [body.name, me, body.memberCount, body.contributionAmount, body.cycleType, body.startDate, newInviteCode(), body.adminCollectsLast],
          );
          const id = rows[0]!.id;
          // Commit the draw before anyone (even the admin) joins; the ledger shows this order.
          await client.query("insert into circle_draws (group_id, commitment, seed) values ($1, $2, $3)", [id, commitmentOf(seed), seed]);
          await client.query("insert into group_members (group_id, user_id) values ($1, $2)", [id, me]);
          const rules = await client.query<{ id: string }>(
            `insert into group_rules (group_id, version, late_fee, grace_days, early_exit_policy, emergency_policy, other_rules, created_by)
             values ($1, 1, $2, $3, $4, $5, $6, $7) returning id`,
            [id, body.rules.lateFee, body.rules.graceDays, body.rules.earlyExitPolicy, body.rules.emergencyPolicy ?? null, body.rules.otherRules ?? null, me],
          );
          await client.query("insert into rule_acceptances (rules_id, user_id) values ($1, $2)", [rules.rows[0]!.id, me]);
          return id;
        } catch (err) {
          const clash = (err as { constraint?: string }).constraint === "groups_invite_code_key";
          if (!clash || attempt >= 5) throw err;
          await client.query("rollback to savepoint new_code");
        }
      }
    });
    return reply.code(201).send(await circleDetail(circleId, me));
  });

  /** What someone sees before joining: enough to decide, nothing private. */
  app.get("/circles/preview/:code", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { code } = codeParam.parse(req.params);
    const { rows } = await pool.query<CircleRow & { admin_name: string | null; commitment: string | null }>(
      `select ${CIRCLE_COLUMNS}, a.full_name as admin_name, d.commitment
         from groups g join users a on a.id = g.admin_id left join circle_draws d on d.group_id = g.id
        where g.invite_code = $1`,
      [code],
    );
    const g = rows[0];
    if (!g) throw new AppError(404, "circle_not_found", "No circle uses that code. Check it and try again.");
    const [members, rules] = await Promise.all([
      pool.query<{ id: string; name: string | null }>(
        `select u.id, u.full_name as name from group_members m join users u on u.id = m.user_id
          where m.group_id = $1 order by m.joined_at`,
        [g.id],
      ),
      pool.query(`select ${RULES_COLUMNS} from group_rules where group_id = $1 order by version desc limit 1`, [g.id]),
    ]);
    return {
      ...circleSummary(g),
      inviteCode: code,
      adminName: g.admin_name,
      drawCommitment: g.commitment,
      alreadyMember: members.rows.some((m) => m.id === me),
      isFull: g.joined >= g.member_count,
      members: members.rows,
      rules: rulesView(rules.rows[0]),
    };
  });

  app.post("/circles/join", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const body = joinBody.parse(req.body);
    await requireProfile(me);
    await verifyPin(pool, me, body.pin);
    const { rows } = await pool.query<{ id: string }>("select join_circle($1, $2, $3, $4) as id", [
      me,
      body.code,
      body.voucherId ?? null,
      body.rulesVersion,
    ]);
    return circleDetail(rows[0]!.id, me);
  });

  app.get("/circles/:id", async (req) => {
    const { id } = idParam.parse(req.params);
    return circleDetail(id, userIdOf(req));
  });

  app.post("/circles/:id/rules/accept", async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const { version } = acceptBody.parse(req.body);
    await loadCircle(id, me);
    await pool.query("select accept_rules($1, $2, $3)", [me, id, version]);
    return circleDetail(id, me);
  });

  app.get("/circles/:id/rounds", async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    await loadCircle(id, me);
    const { rows } = await pool.query(
      `select r.round_number as number, r.status, r.due_date::text as "dueDate",
              r.collector_id as "collectorId", u.full_name as "collectorName",
              r.payout_received as "payoutReceived", r.payout_confirmed_at as "payoutConfirmedAt",
              (select count(*)::int from contributions c where c.round_id = r.id and c.status in ('payer_confirmed', 'fully_confirmed')) as "paidCount",
              (select count(*)::int from contributions c where c.round_id = r.id and c.status = 'fully_confirmed') as "confirmedCount"
         from rounds r join users u on u.id = r.collector_id
        where r.group_id = $1 order by r.round_number`,
      [id],
    );
    return { rounds: rows };
  });

  app.post("/circles/:id/rounds/:number/pay", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id, number } = roundParam.parse(req.params);
    const body = payBody.parse(req.body);
    await loadCircle(id, me);
    if (body.proofKey) {
      const valid = new RegExp(`^${proofPrefix(id, number, me)}[0-9a-f-]{36}[.](jpg|png|webp)$`).test(body.proofKey);
      if (!valid || !(await requireStorage().exists(body.proofKey))) {
        throw new AppError(400, "proof_missing", "We couldn't find that photo. Please attach it again.");
      }
    }
    await verifyPin(pool, me, body.pin);
    await pool.query("select record_contribution($1, $2, $3, $4)", [
      me,
      await roundId(id, number),
      body.bankReference ?? null,
      body.proofKey ?? null,
    ]);
    return circleDetail(id, me);
  });

  /** A short-lived link to upload a receipt photo straight to the private bucket. */
  app.post("/circles/:id/rounds/:number/proof", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id, number } = roundParam.parse(req.params);
    const { contentType, size } = proofBody.parse(req.body);
    await loadCircle(id, me);
    await roundId(id, number);
    const key = `${proofPrefix(id, number, me)}${randomUUID()}.${PROOF_TYPES[contentType]}`;
    return { key, uploadUrl: await requireStorage().uploadUrl(key, contentType, size), headers: { "Content-Type": contentType } };
  });

  /** A short-lived link to view a payment's receipt photo, for members of the circle. */
  app.get("/contributions/:id/proof", async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const { rows } = await pool.query<{ proof_url: string | null }>(
      `select c.proof_url from contributions c join group_members m on m.group_id = c.group_id and m.user_id = $2
        where c.id = $1`,
      [id, me],
    );
    if (!rows[0]) throw notFound("Payment");
    if (!rows[0].proof_url) throw new AppError(404, "no_proof", "No photo was attached to this payment.");
    return { url: await requireStorage().viewUrl(rows[0].proof_url) };
  });

  app.post("/contributions/:id/confirm", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const { pin: pinValue } = pinBody.parse(req.body);
    const { rows } = await pool.query<{ group_id: string }>(
      `select c.group_id from contributions c join group_members m on m.group_id = c.group_id and m.user_id = $2
        where c.id = $1`,
      [id, me],
    );
    if (!rows[0]) throw notFound("Payment");
    await verifyPin(pool, me, pinValue);
    await pool.query("select confirm_contribution($1, $2)", [me, id]);
    return circleDetail(rows[0].group_id, me);
  });

  app.post("/circles/:id/rounds/:number/payout", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id, number } = roundParam.parse(req.params);
    const body = payoutBody.parse(req.body);
    await loadCircle(id, me);
    await verifyPin(pool, me, body.pin);
    const { rows } = await pool.query<{ shortfall: number; dispute_id: string | null; next_round: number | null }>(
      "select * from close_round($1, $2, $3)",
      [me, await roundId(id, number), body.amount],
    );
    const result = rows[0]!;
    return {
      shortfall: result.shortfall,
      disputeId: result.dispute_id,
      nextRound: result.next_round,
      circle: await circleDetail(id, me),
    };
  });

  /** Everything a member sees on the circle screen. */
  async function circleDetail(circleId: string, me: string) {
    const g = await loadCircle(circleId, me);
    const [members, rules, draw, round, disputes, rounds, contributions] = await Promise.all([
      pool.query<{
        id: string;
        name: string | null;
        phone: string;
        position: number | null;
        accepted: boolean;
        voucher_id: string | null;
        voucher_name: string | null;
        owes_after_collecting: boolean;
      }>(
        `with current_rules as (select id from group_rules where group_id = $1 order by version desc limit 1)
         select u.id, u.full_name as name, u.phone, m.payout_position as position,
                exists (select 1 from rule_acceptances a where a.rules_id = (select id from current_rules) and a.user_id = u.id) as accepted,
                v.voucher_id, vu.full_name as voucher_name,
                exists (select 1 from unfinished_obligations o where o.group_id = $1 and o.user_id = u.id) as owes_after_collecting
           from group_members m
           join users u on u.id = m.user_id
           left join vouches v on v.group_id = m.group_id and v.vouchee_id = m.user_id
           left join users vu on vu.id = v.voucher_id
          where m.group_id = $1
          order by m.payout_position nulls last, m.joined_at`,
        [circleId],
      ),
      pool.query(`select ${RULES_COLUMNS} from group_rules where group_id = $1 order by version desc limit 1`, [circleId]),
      pool.query<{ commitment: string; seed: string; revealed_at: Date | null }>(
        "select commitment, seed, revealed_at from circle_draws where group_id = $1",
        [circleId],
      ),
      pool.query<{
        id: string;
        number: number;
        due_date: string;
        collector_id: string;
        collector_name: string | null;
        bank_name: string | null;
        account_number: string | null;
        account_name: string | null;
      }>(
        `select r.id, r.round_number as number, r.due_date::text, r.collector_id, u.full_name as collector_name,
                u.bank_name, u.account_number, u.account_name
           from rounds r join users u on u.id = r.collector_id
          where r.group_id = $1 and r.status = 'active'`,
        [circleId],
      ),
      pool.query<{ n: number }>("select count(*)::int as n from disputes where group_id = $1 and status = 'open'", [circleId]),
      pool.query(
        `select id, round_number as number, collector_id as "collectorId", due_date::text as "dueDate", status,
                payout_received as "payoutReceived", payout_confirmed_at as "payoutConfirmedAt"
           from rounds where group_id = $1 order by round_number`,
        [circleId],
      ),
      pool.query(
        `select id, round_id as "roundId", user_id as "userId", amount, status, bank_reference as "bankReference",
                proof_url is not null as "hasProof", payer_confirmed_at as "paidAt", collector_confirmed_at as "confirmedAt"
           from contributions where group_id = $1 order by created_at`,
        [circleId],
      ),
    ]);

    const current = round.rows[0];
    let currentRound = null;
    if (current) {
      const { rows: paid } = await pool.query<{
        id: string;
        user_id: string;
        status: string;
        bank_reference: string | null;
        proof_url: string | null;
        payer_confirmed_at: Date | null;
        collector_confirmed_at: Date | null;
      }>(
        `select id, user_id, status, bank_reference, proof_url, payer_confirmed_at, collector_confirmed_at
           from contributions where round_id = $1`,
        [current.id],
      );
      const byUser = new Map(paid.map((c) => [c.user_id, c]));
      currentRound = {
        id: current.id,
        number: current.number,
        dueDate: current.due_date,
        payoutAmount: g.contribution_amount * (g.member_count - 1),
        isMyTurn: current.collector_id === me,
        collector: {
          id: current.collector_id,
          name: current.collector_name,
          bank: current.account_number
            ? { bankName: current.bank_name, accountNumber: current.account_number, accountName: current.account_name }
            : null,
        },
        contributions: members.rows
          .filter((m) => m.id !== current.collector_id)
          .map((m) => {
            const c = byUser.get(m.id);
            return {
              id: c?.id ?? null,
              userId: m.id,
              name: m.name,
              status: c?.status ?? "unpaid",
              bankReference: c?.bank_reference ?? null,
              hasProof: Boolean(c?.proof_url),
              paidAt: c?.payer_confirmed_at ?? null,
              confirmedAt: c?.collector_confirmed_at ?? null,
            };
          }),
      };
    }

    const d = draw.rows[0];
    return {
      ...circleSummary(g),
      isAdmin: g.admin_id === me,
      myPosition: g.my_position,
      members: members.rows.map((m) => ({
        id: m.id,
        name: m.name,
        phone: m.phone,
        position: m.position,
        isAdmin: m.id === g.admin_id,
        acceptedRules: m.accepted,
        vouchedBy: m.voucher_id ? { id: m.voucher_id, name: m.voucher_name } : null,
        owesAfterCollecting: m.owes_after_collecting,
      })),
      rules: { ...rulesView(rules.rows[0]), acceptedByMe: members.rows.find((m) => m.id === me)?.accepted ?? false },
      // The seed stays secret until the draw; the commitment proves it was fixed in advance.
      draw: d ? { commitment: d.commitment, revealedAt: d.revealed_at, seed: d.revealed_at ? d.seed : null } : null,
      currentRound,
      openDisputes: disputes.rows[0]!.n,
      /** Full history, so the app can show receipts, activity and the member's record. */
      rounds: rounds.rows,
      contributions: contributions.rows,
    };
  }
}
