import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";

import { requireUser, userIdOf } from "../auth/plugin.js";
import { verifyPin } from "../auth/pin.js";
import type { TokenService } from "../auth/tokens.js";
import { notFound } from "../lib/errors.js";
import { normalisePhone } from "../lib/phone.js";

/**
 * Swapping turns and handing over a place. The rules live in the database
 * (request_swap, respond_swap, cancel_swap, request_handover,
 * respond_handover, decide_handover, cancel_handover; see
 * db/migrations/20261008000000_swaps_handovers.sql). Anything that changes
 * who collects when needs the PIN.
 */

const pin = z.string().regex(/^\d{4}$/, "Your PIN is 4 digits.");
const uuid = z.uuid("Not a valid id.");
const idParam = z.object({ id: uuid });
const reason = z.string().trim().max(500, "Keep it under 500 characters.").nullish();
const swapBody = z.object({ targetId: uuid, reason, pin });
const handoverBody = z.object({
  phone: z
    .string()
    .max(30)
    .transform((v, ctx) => {
      const phone = normalisePhone(v);
      if (!phone) {
        ctx.addIssue({ code: "custom", message: "Enter a Nigerian mobile number, like 0803 123 4567." });
        return z.NEVER;
      }
      return phone;
    }),
  reason,
  pin,
});
const pinBody = z.object({ pin });
const acceptHandoverBody = z.object({ rulesVersion: z.number().int().positive(), pin });
const limited = { rateLimit: { max: 30, timeWindow: "1 minute" } };

interface SwapRow {
  id: string;
  status: string;
  reason: string | null;
  created_at: Date;
  responded_at: Date | null;
  requester_id: string;
  requester_name: string | null;
  requester_turn: number | null;
  target_id: string;
  target_name: string | null;
  target_turn: number | null;
}

interface HandoverRow {
  id: string;
  group_id: string;
  status: string;
  reason: string | null;
  created_at: Date;
  leaving_id: string;
  leaving_name: string | null;
  replacement_id: string;
  replacement_name: string | null;
  turn: number | null;
  paid_in: number;
}

export async function turnRoutes(app: FastifyInstance, opts: { pool: pg.Pool; tokens: TokenService }) {
  const { pool } = opts;
  app.addHook("preHandler", requireUser(opts.tokens));

  const requireMember = async (circleId: string, me: string) => {
    const { rows } = await pool.query<{ admin_id: string }>(
      "select g.admin_id from groups g join group_members m on m.group_id = g.id and m.user_id = $2 where g.id = $1",
      [circleId, me],
    );
    if (!rows[0]) throw notFound("Circle");
    return rows[0].admin_id;
  };

  const HANDOVER_SELECT = `
    select h.id, h.group_id, h.status, h.reason, h.created_at,
           h.leaving_user_id as leaving_id, lu.full_name as leaving_name,
           h.replacement_user_id as replacement_id, ru.full_name as replacement_name,
           coalesce(h.position, (select payout_position from group_members m
                                  where m.group_id = h.group_id and m.user_id = h.leaving_user_id)) as turn,
           (select coalesce(sum(c.amount), 0)::int from contributions c
             where c.group_id = h.group_id and c.user_id = h.leaving_user_id and c.status = 'fully_confirmed') as paid_in
      from handover_requests h
      join users lu on lu.id = h.leaving_user_id
      join users ru on ru.id = h.replacement_user_id`;

  /** Everything changing who collects when, for the circle screen. */
  async function turnChanges(circleId: string, me: string) {
    const adminId = await requireMember(circleId, me);
    const [swaps, handovers] = await Promise.all([
      pool.query<SwapRow>(
        `select s.id, s.status, s.reason, s.created_at, s.responded_at,
                s.requester_id, ru.full_name as requester_name, rm.payout_position as requester_turn,
                s.target_id, tu.full_name as target_name, tm.payout_position as target_turn
           from swap_requests s
           join users ru on ru.id = s.requester_id
           join users tu on tu.id = s.target_id
           left join group_members rm on rm.group_id = s.group_id and rm.user_id = s.requester_id
           left join group_members tm on tm.group_id = s.group_id and tm.user_id = s.target_id
          where s.group_id = $1
          order by (s.status = 'pending') desc, s.created_at desc limit 50`,
        [circleId],
      ),
      pool.query<HandoverRow>(
        `${HANDOVER_SELECT} where h.group_id = $1
          order by (h.status in ('pending', 'accepted', 'approved')) desc, h.created_at desc limit 50`,
        [circleId],
      ),
    ]);
    const person = (id: string, name: string | null, turn?: number | null) => ({ id, name: name ?? "Member", turn: turn ?? null });
    return {
      swaps: swaps.rows.map((s) => ({
        id: s.id,
        status: s.status,
        reason: s.reason,
        createdAt: s.created_at,
        respondedAt: s.responded_at,
        requester: person(s.requester_id, s.requester_name, s.requester_turn),
        target: person(s.target_id, s.target_name, s.target_turn),
        canAnswer: s.status === "pending" && s.target_id === me,
        canCancel: s.status === "pending" && s.requester_id === me,
      })),
      handovers: handovers.rows.map((h) => ({
        id: h.id,
        status: h.status,
        reason: h.reason,
        createdAt: h.created_at,
        leaving: person(h.leaving_id, h.leaving_name, h.turn),
        replacement: person(h.replacement_id, h.replacement_name),
        /** What the leaving member paid into earlier turns; they settle it with the replacement themselves. */
        paidIn: h.paid_in,
        canApprove: h.status === "accepted" && adminId === me,
        canCancel: ["pending", "accepted", "approved"].includes(h.status) && h.leaving_id === me,
      })),
    };
  }

  const circleOfSwap = async (swapId: string) => {
    const { rows } = await pool.query<{ group_id: string }>("select group_id from swap_requests where id = $1", [swapId]);
    if (!rows[0]) throw notFound("Swap request");
    return rows[0].group_id;
  };
  const circleOfHandover = async (handoverId: string) => {
    const { rows } = await pool.query<{ group_id: string }>("select group_id from handover_requests where id = $1", [handoverId]);
    if (!rows[0]) throw notFound("Handover");
    return rows[0].group_id;
  };

  app.get("/circles/:id/turn-changes", async (req) => {
    const { id } = idParam.parse(req.params);
    return turnChanges(id, userIdOf(req));
  });

  app.post("/circles/:id/swaps", { config: limited }, async (req, reply) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const body = swapBody.parse(req.body);
    await requireMember(id, me);
    await verifyPin(pool, me, body.pin);
    await pool.query("select request_swap($1, $2, $3, $4)", [me, id, body.targetId, body.reason ?? null]);
    return reply.code(201).send(await turnChanges(id, me));
  });

  app.post("/swaps/:id/accept", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const { pin: pinValue } = pinBody.parse(req.body);
    const circleId = await circleOfSwap(id);
    await requireMember(circleId, me);
    await verifyPin(pool, me, pinValue);
    await pool.query("select respond_swap($1, $2, true)", [me, id]);
    return turnChanges(circleId, me);
  });

  app.post("/swaps/:id/decline", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const circleId = await circleOfSwap(id);
    await requireMember(circleId, me);
    await pool.query("select respond_swap($1, $2, false)", [me, id]);
    return turnChanges(circleId, me);
  });

  app.post("/swaps/:id/cancel", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const circleId = await circleOfSwap(id);
    await requireMember(circleId, me);
    await pool.query("select cancel_swap($1, $2)", [me, id]);
    return turnChanges(circleId, me);
  });

  app.post("/circles/:id/handovers", { config: limited }, async (req, reply) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const body = handoverBody.parse(req.body);
    await requireMember(id, me);
    await verifyPin(pool, me, body.pin);
    await pool.query("select request_handover($1, $2, $3, $4)", [me, id, body.phone, body.reason ?? null]);
    return reply.code(201).send(await turnChanges(id, me));
  });

  /** Places offered to the signed-in person, who isn't in those circles yet. */
  async function offers(me: string) {
    const { rows } = await pool.query<
      HandoverRow & {
        circle_name: string;
        contribution_amount: number;
        member_count: number;
        cycle_type: string;
        circle_status: string;
        rules_version: number;
        late_fee: number;
        grace_days: number;
        early_exit_policy: string;
        emergency_policy: string | null;
      }
    >(
      `select h.id, h.group_id, h.status, h.reason, h.created_at,
              h.leaving_user_id as leaving_id, lu.full_name as leaving_name,
              h.replacement_user_id as replacement_id, null as replacement_name,
              m.payout_position as turn,
              (select coalesce(sum(c.amount), 0)::int from contributions c
                where c.group_id = h.group_id and c.user_id = h.leaving_user_id and c.status = 'fully_confirmed') as paid_in,
              g.name as circle_name, g.contribution_amount, g.member_count, g.cycle_type, g.status as circle_status,
              r.version as rules_version, r.late_fee, r.grace_days, r.early_exit_policy, r.emergency_policy
         from handover_requests h
         join users lu on lu.id = h.leaving_user_id
         join groups g on g.id = h.group_id
         left join group_members m on m.group_id = h.group_id and m.user_id = h.leaving_user_id
         left join lateral (select * from group_rules where group_id = g.id order by version desc limit 1) r on true
        where h.replacement_user_id = $1 and h.status = 'pending'
        order by h.created_at desc`,
      [me],
    );
    return {
      offers: rows.map((h) => ({
        id: h.id,
        reason: h.reason,
        createdAt: h.created_at,
        leaving: { id: h.leaving_id, name: h.leaving_name ?? "Member" },
        turn: h.turn,
        paidIn: h.paid_in,
        circle: {
          id: h.group_id,
          name: h.circle_name,
          status: h.circle_status,
          contributionAmount: h.contribution_amount,
          payoutAmount: h.contribution_amount * (h.member_count - 1),
          memberCount: h.member_count,
          cycleType: h.cycle_type,
        },
        rules: {
          version: h.rules_version,
          lateFee: h.late_fee,
          graceDays: h.grace_days,
          earlyExitPolicy: h.early_exit_policy,
          emergencyPolicy: h.emergency_policy,
        },
      })),
    };
  }

  app.get("/me/handover-offers", async (req) => offers(userIdOf(req)));

  app.post("/handovers/:id/accept", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const body = acceptHandoverBody.parse(req.body);
    await circleOfHandover(id);
    await verifyPin(pool, me, body.pin);
    await pool.query("select respond_handover($1, $2, true, $3)", [me, id, body.rulesVersion]);
    return offers(me);
  });

  app.post("/handovers/:id/decline", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    await circleOfHandover(id);
    await pool.query("select respond_handover($1, $2, false, null)", [me, id]);
    return offers(me);
  });

  app.post("/handovers/:id/approve", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const { pin: pinValue } = pinBody.parse(req.body);
    const circleId = await circleOfHandover(id);
    await requireMember(circleId, me);
    await verifyPin(pool, me, pinValue);
    await pool.query("select decide_handover($1, $2, true)", [me, id]);
    return turnChanges(circleId, me);
  });

  app.post("/handovers/:id/reject", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const circleId = await circleOfHandover(id);
    await requireMember(circleId, me);
    await pool.query("select decide_handover($1, $2, false)", [me, id]);
    return turnChanges(circleId, me);
  });

  app.post("/handovers/:id/cancel", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const circleId = await circleOfHandover(id);
    await requireMember(circleId, me);
    await pool.query("select cancel_handover($1, $2)", [me, id]);
    return turnChanges(circleId, me);
  });
}
