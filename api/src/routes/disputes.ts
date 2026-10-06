import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";

import { requireUser, userIdOf } from "../auth/plugin.js";
import { verifyPin } from "../auth/pin.js";
import type { TokenService } from "../auth/tokens.js";
import { notFound } from "../lib/errors.js";

/**
 * Disputes: the rules live in the database (raise_payment_dispute,
 * cast_dispute_vote, concede_dispute, add_dispute_comment; see
 * db/migrations/20261006000000_dispute_votes.sql). These routes check
 * membership, ask for the PIN on anything that changes a payment's record,
 * and return the dispute as the member sees it.
 */

const pin = z.string().regex(/^\d{4}$/, "Your PIN is 4 digits.");
const idParam = z.object({ id: z.uuid("Not a valid id.") });
const raiseBody = z.object({
  reason: z.string().trim().min(3, "Say what went wrong.").max(500, "Keep it under 500 characters."),
  pin,
});
const voteBody = z.object({ side: z.enum(["payer", "collector"]), pin });
const pinBody = z.object({ pin });
const commentBody = z.object({
  message: z.string().trim().min(1, "Write a message.").max(500, "Keep it under 500 characters."),
});

const limited = { rateLimit: { max: 30, timeWindow: "1 minute" } };

interface DisputeRow {
  id: string;
  group_id: string;
  kind: "shortfall" | "payment";
  status: string;
  reason: string;
  resolution_note: string | null;
  created_at: Date;
  resolved_at: Date | null;
  turn: number | null;
  raised_by: string;
  raised_by_name: string | null;
  collector_id: string;
  collector_name: string | null;
  contribution_id: string | null;
  amount: number | null;
  bank_reference: string | null;
  has_proof: boolean | null;
  paid_at: Date | null;
}

const person = (id: string, name: string | null) => ({ id, name: name ?? "Member" });

export async function disputeRoutes(app: FastifyInstance, opts: { pool: pg.Pool; tokens: TokenService }) {
  const { pool } = opts;
  app.addHook("preHandler", requireUser(opts.tokens));

  const SELECT = `
    select d.id, d.group_id, d.kind, d.status, d.reason, d.resolution_note, d.created_at, d.resolved_at,
           r.round_number as turn, d.raised_by, rb.full_name as raised_by_name,
           r.collector_id, col.full_name as collector_name,
           c.id as contribution_id, c.amount, c.bank_reference, c.proof_url is not null as has_proof,
           c.payer_confirmed_at as paid_at
      from disputes d
      join rounds r on r.id = d.round_id
      join users rb on rb.id = d.raised_by
      join users col on col.id = r.collector_id
      left join contributions c on c.id = d.contribution_id`;

  /** Members only; anyone else gets 404 so ids reveal nothing. */
  const groupOfDispute = async (disputeId: string, me: string) => {
    const { rows } = await pool.query<{ group_id: string }>(
      `select d.group_id from disputes d join group_members m on m.group_id = d.group_id and m.user_id = $2 where d.id = $1`,
      [disputeId, me],
    );
    if (!rows[0]) throw notFound("Dispute");
    return rows[0].group_id;
  };

  async function view(d: DisputeRow, me: string, withTimeline: boolean) {
    const [payers, votes, eligible, events] = await Promise.all([
      pool.query<{ id: string; name: string | null }>(
        "select u.id, u.full_name as name from dispute_payers($1) p(id) join users u on u.id = p.id order by u.full_name",
        [d.id],
      ),
      pool.query<{ voter_id: string; name: string | null; side: "payer" | "collector"; updated_at: Date }>(
        `select v.voter_id, u.full_name as name, v.side, v.updated_at
           from dispute_votes v join users u on u.id = v.voter_id where v.dispute_id = $1 order by v.updated_at`,
        [d.id],
      ),
      pool.query<{ n: number }>("select dispute_eligible_voters($1) as n", [d.id]),
      withTimeline
        ? pool.query<{ actor_id: string; name: string | null; kind: string; message: string | null; created_at: Date }>(
            `select e.actor_id, u.full_name as name, e.kind, e.message, e.created_at
               from dispute_events e join users u on u.id = e.actor_id where e.dispute_id = $1 order by e.created_at, e.id`,
            [d.id],
          )
        : null,
    ]);
    const open = d.status === "open";
    const isCollector = d.collector_id === me;
    const isPayer = payers.rows.some((p) => p.id === me);
    const role = isCollector ? "collector" : isPayer ? "payer" : "voter";
    const count = (side: string) => votes.rows.filter((v) => v.side === side).length;
    const eligibleVoters = eligible.rows[0]!.n;

    return {
      id: d.id,
      circleId: d.group_id,
      kind: d.kind,
      status: d.status,
      turn: d.turn,
      reason: d.reason,
      resolutionNote: d.resolution_note,
      createdAt: d.created_at,
      resolvedAt: d.resolved_at,
      raisedBy: person(d.raised_by, d.raised_by_name),
      collector: person(d.collector_id, d.collector_name),
      /** The payer of a payment dispute, or everyone still missing for a shortfall. */
      payers: payers.rows.map((p) => person(p.id, p.name)),
      payment: d.contribution_id
        ? { id: d.contribution_id, amount: d.amount, bankReference: d.bank_reference, hasProof: d.has_proof, paidAt: d.paid_at }
        : null,
      myRole: role,
      votes: {
        payer: count("payer"),
        collector: count("collector"),
        eligible: eligibleVoters,
        /** Votes one side needs to win: more than half of the eligible voters. */
        needed: Math.floor(eligibleVoters / 2) + 1,
        mine: votes.rows.find((v) => v.voter_id === me)?.side ?? null,
        cast: votes.rows.map((v) => ({ voter: person(v.voter_id, v.name), side: v.side, at: v.updated_at })),
      },
      canVote: open && d.kind === "payment" && role === "voter",
      canSettle: open && (isCollector || (d.kind === "payment" && isPayer)),
      timeline: events?.rows.map((e) => ({ actor: person(e.actor_id, e.name), kind: e.kind, message: e.message, at: e.created_at })),
    };
  }

  const detail = async (disputeId: string, me: string) => {
    const { rows } = await pool.query<DisputeRow>(`${SELECT} where d.id = $1`, [disputeId]);
    return view(rows[0]!, me, true);
  };

  app.get("/circles/:id/disputes", async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const member = await pool.query("select 1 from group_members where group_id = $1 and user_id = $2", [id, me]);
    if (!member.rowCount) throw notFound("Circle");
    const { rows } = await pool.query<DisputeRow>(
      `${SELECT} where d.group_id = $1 order by (d.status = 'open') desc, d.created_at desc`,
      [id],
    );
    return { disputes: await Promise.all(rows.map((d) => view(d, me, false))) };
  });

  app.get("/disputes/:id", async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    await groupOfDispute(id, me);
    return detail(id, me);
  });

  /** The collector says a payment hasn't arrived, or the payer says it isn't being confirmed. */
  app.post("/contributions/:id/dispute", { config: limited }, async (req, reply) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const body = raiseBody.parse(req.body);
    const { rows } = await pool.query(
      "select 1 from contributions c join group_members m on m.group_id = c.group_id and m.user_id = $2 where c.id = $1",
      [id, me],
    );
    if (!rows[0]) throw notFound("Payment");
    await verifyPin(pool, me, body.pin);
    const raised = await pool.query<{ id: string }>("select raise_payment_dispute($1, $2, $3) as id", [me, id, body.reason]);
    return reply.code(201).send(await detail(raised.rows[0]!.id, me));
  });

  app.post("/disputes/:id/vote", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const body = voteBody.parse(req.body);
    await groupOfDispute(id, me);
    await verifyPin(pool, me, body.pin);
    await pool.query("select cast_dispute_vote($1, $2, $3)", [me, id, body.side]);
    return detail(id, me);
  });

  /** A party agrees with the other side, which closes the dispute. */
  app.post("/disputes/:id/settle", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const body = pinBody.parse(req.body);
    await groupOfDispute(id, me);
    await verifyPin(pool, me, body.pin);
    await pool.query("select concede_dispute($1, $2)", [me, id]);
    return detail(id, me);
  });

  app.post("/disputes/:id/comments", { config: limited }, async (req) => {
    const me = userIdOf(req);
    const { id } = idParam.parse(req.params);
    const { message } = commentBody.parse(req.body);
    await groupOfDispute(id, me);
    await pool.query("select add_dispute_comment($1, $2, $3)", [me, id, message]);
    return detail(id, me);
  });
}
