import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";

import { requireUser, userIdOf } from "../auth/plugin.js";
import type { TokenService } from "../auth/tokens.js";
import {
  AssistantUnavailable,
  dateInLagos,
  naira,
  shortName,
  systemPrompt,
  type Assistant,
  type ChatMessage,
} from "../lib/assistant.js";
import { AppError, notFound } from "../lib/errors.js";

const explainBody = z
  .object({
    topic: z.enum(["circle", "dispute", "question"]),
    circleId: z.uuid("Not a valid id.").optional(),
    disputeId: z.uuid("Not a valid id.").optional(),
    question: z.string().trim().min(3, "Type a question.").max(300, "Keep the question under 300 characters.").optional(),
    language: z.enum(["en", "pcm"]).default("en"),
  })
  .superRefine((b, ctx) => {
    if (b.topic === "circle" && !b.circleId) ctx.addIssue({ code: "custom", path: ["circleId"], message: "Choose a circle." });
    if (b.topic === "dispute" && !b.disputeId) ctx.addIssue({ code: "custom", path: ["disputeId"], message: "Choose a dispute." });
    if (b.topic === "question" && !b.question) ctx.addIssue({ code: "custom", path: ["question"], message: "Type a question." });
  });

const EXIT_POLICIES: Record<string, string> = {
  find_replacement: "a member who leaves must hand their place to someone the admin approves",
  refund_after_cycle: "a member who leaves is paid back what they put in after the cycle ends",
  forfeit_fee: "a member who leaves pays a fee",
};

const CONTRIBUTION_STATES: Record<string, string> = {
  payer_confirmed: "marked as sent, waiting for the collector to confirm",
  fully_confirmed: "confirmed by the collector",
  disputed: "under dispute",
};

/** Per-user answers a day, on top of the per-IP limit; counted in memory (resets on restart). */
class DailyCounter {
  private day = "";
  private counts = new Map<string, number>();
  constructor(private readonly limit: number) {}
  take(userId: string): boolean {
    const today = new Date().toISOString().slice(0, 10);
    if (today !== this.day) {
      this.day = today;
      this.counts.clear();
    }
    const used = this.counts.get(userId) ?? 0;
    if (used >= this.limit) return false;
    this.counts.set(userId, used + 1);
    return true;
  }
}

/**
 * POST /assistant/explain: "Ask Sova" explains a circle, a dispute or a
 * question about how Sova works. Members only (404 otherwise, like every
 * circle route). The answer is a suggestion written by a model; the app labels
 * it as such and the circle screen stays the record.
 */
export async function assistantRoutes(
  app: FastifyInstance,
  opts: { pool: pg.Pool; tokens: TokenService; assistant: Assistant | null; dailyLimit: number },
) {
  const { pool, assistant } = opts;
  const daily = new DailyCounter(opts.dailyLimit);
  app.addHook("preHandler", requireUser(opts.tokens));

  async function circleData(circleId: string, me: string): Promise<string> {
    const { rows: circles } = await pool.query<{
      name: string;
      status: string;
      contribution_amount: number;
      cycle_type: string;
      member_count: number;
      start_date: string;
      admin_id: string;
      admin_collects_last: boolean;
    }>(
      `select g.name, g.status, g.contribution_amount, g.cycle_type, g.member_count, g.start_date::text,
              g.admin_id, g.admin_collects_last
         from groups g join group_members m on m.group_id = g.id and m.user_id = $2
        where g.id = $1`,
      [circleId, me],
    );
    const g = circles[0];
    if (!g) throw notFound("Circle");

    const [members, rules, rounds, disputes] = await Promise.all([
      pool.query<{ id: string; name: string | null; position: number | null }>(
        `select u.id, u.full_name as name, m.payout_position as position
           from group_members m join users u on u.id = m.user_id
          where m.group_id = $1 order by m.payout_position nulls last, m.joined_at`,
        [circleId],
      ),
      pool.query<{
        late_fee: number;
        grace_days: number;
        early_exit_policy: string;
        emergency_policy: string | null;
        other_rules: string | null;
      }>(
        `select late_fee, grace_days, early_exit_policy, emergency_policy, other_rules
           from group_rules where group_id = $1 order by version desc limit 1`,
        [circleId],
      ),
      pool.query<{ id: string; number: number; collector_id: string; status: string; due_date: string }>(
        `select id, round_number as number, collector_id, status, due_date::text
           from rounds where group_id = $1 order by round_number`,
        [circleId],
      ),
      pool.query<{ n: number }>("select count(*)::int as n from disputes where group_id = $1 and status = 'open'", [circleId]),
    ]);

    const nameOf = new Map(members.rows.map((m) => [m.id, shortName(m.name)]));
    const lines = [
      `Circle: ${g.name} (status: ${g.status})`,
      `Contribution: ${naira(g.contribution_amount)} per member, ${g.cycle_type}`,
      `Members: ${members.rows.length} of ${g.member_count} joined`,
      `Payout each turn: ${naira(g.contribution_amount * (g.member_count - 1))} (one contribution from each of the other ${g.member_count - 1} members)`,
      `Planned start: ${dateInLagos(g.start_date)}`,
      `Admin: ${nameOf.get(g.admin_id) ?? "A member"}${g.admin_collects_last ? " (promised to collect last)" : ""}`,
    ];

    const r = rules.rows[0];
    if (r) {
      lines.push(
        `Rules: late fee ${naira(r.late_fee)}, ${r.grace_days} grace day(s); ${EXIT_POLICIES[r.early_exit_policy] ?? r.early_exit_policy}.` +
          (r.emergency_policy ? ` Emergencies: ${r.emergency_policy.slice(0, 300)}.` : "") +
          (r.other_rules ? ` Other rules: ${r.other_rules.slice(0, 500)}` : ""),
      );
    }

    const byCollector = new Map(rounds.rows.map((t) => [t.collector_id, t]));
    if (rounds.rows.length) {
      const order = members.rows
        .filter((m) => m.position !== null)
        .map((m) => {
          const t = byCollector.get(m.id);
          const state = t?.status === "completed" ? "collected" : t?.status === "active" ? "collecting now" : "waiting";
          return `${m.position}. ${nameOf.get(m.id)} (${state})`;
        });
      lines.push(`Payout order: ${order.join("; ")}`);
    } else {
      lines.push("Payout order: not drawn yet (it is drawn when the circle is full)");
    }

    const current = rounds.rows.find((t) => t.status === "active");
    if (current) {
      const { rows: paid } = await pool.query<{ user_id: string; status: string }>(
        "select user_id, status from contributions where round_id = $1",
        [current.id],
      );
      const statusOf = new Map(paid.map((c) => [c.user_id, c.status]));
      const payments = members.rows
        .filter((m) => m.id !== current.collector_id)
        .map((m) => `${nameOf.get(m.id)}: ${CONTRIBUTION_STATES[statusOf.get(m.id) ?? ""] ?? "not paid yet"}`);
      lines.push(
        `Current turn: ${current.number} of ${g.member_count}, due ${dateInLagos(current.due_date)}, collector ${nameOf.get(current.collector_id)}`,
        `Payments this turn: ${payments.join("; ")}`,
      );
    }
    lines.push(`Open disputes: ${disputes.rows[0]!.n}`);

    const mine = members.rows.find((m) => m.id === me);
    const myTurn = mine ? byCollector.get(me) : undefined;
    lines.push(
      `The member asking: ${nameOf.get(me)}` +
        (mine?.position ? `, turn ${mine.position} in the order` : "") +
        (myTurn?.status === "completed" ? " (already collected)" : "") +
        (current?.collector_id === me ? " (collecting this turn)" : ""),
    );
    return lines.join("\n");
  }

  async function disputeData(disputeId: string, me: string): Promise<{ circleId: string; text: string }> {
    const { rows } = await pool.query<{
      group_id: string;
      circle_name: string;
      kind: string;
      status: string;
      reason: string | null;
      turn: number;
      raised_by_name: string | null;
      collector_id: string;
      collector_name: string | null;
      amount: number | null;
      contribution_amount: number;
    }>(
      `select d.group_id, g.name as circle_name, d.kind, d.status, d.reason, r.round_number as turn,
              rb.full_name as raised_by_name, r.collector_id, col.full_name as collector_name,
              c.amount, g.contribution_amount
         from disputes d
         join group_members m on m.group_id = d.group_id and m.user_id = $2
         join groups g on g.id = d.group_id
         join rounds r on r.id = d.round_id
         join users rb on rb.id = d.raised_by
         join users col on col.id = r.collector_id
         left join contributions c on c.id = d.contribution_id
        where d.id = $1`,
      [disputeId, me],
    );
    const d = rows[0];
    if (!d) throw notFound("Dispute");

    const [payers, votes, eligible] = await Promise.all([
      pool.query<{ id: string; name: string | null }>(
        "select u.id, u.full_name as name from dispute_payers($1) p(id) join users u on u.id = p.id",
        [disputeId],
      ),
      pool.query<{ side: string; n: number }>(
        "select side, count(*)::int as n from dispute_votes where dispute_id = $1 group by side",
        [disputeId],
      ),
      pool.query<{ n: number }>("select dispute_eligible_voters($1) as n", [disputeId]),
    ]);
    const count = (side: string) => votes.rows.find((v) => v.side === side)?.n ?? 0;
    const voters = eligible.rows[0]!.n;
    const role =
      d.collector_id === me ? "the collector" : payers.rows.some((p) => p.id === me) ? "the payer" : "a voter";

    const lines = [
      `Circle: ${d.circle_name}`,
      d.kind === "shortfall"
        ? `Dispute: the turn ${d.turn} payout was short. Members who had not paid: ${payers.rows.map((p) => shortName(p.name)).join(", ") || "none"}. There is no vote: it closes when every missing payment is confirmed, or the collector marks it settled.`
        : `Dispute: a payment of ${naira(d.amount ?? d.contribution_amount)} for turn ${d.turn} from ${payers.rows.map((p) => shortName(p.name)).join(", ")} to the collector ${shortName(d.collector_name)}. The payment is frozen until this is decided.`,
      `Raised by: ${shortName(d.raised_by_name)}`,
      `Status: ${d.status}`,
    ];
    if (d.reason) lines.push(`Reason given: ${d.reason.slice(0, 500)}`);
    if (d.kind === "payment") {
      lines.push(
        `Votes: ${count("payer")} say it arrived, ${count("collector")} say it didn't, out of ${voters} members who can vote; ${Math.floor(voters / 2) + 1} votes decide.`,
        'Outcome: "it arrived" confirms the payment; "it didn\'t arrive" puts it back to unpaid.',
      );
    }
    lines.push(`The member asking is ${role} in this dispute.`);
    return { circleId: d.group_id, text: lines.join("\n") };
  }

  app.post(
    "/assistant/explain",
    { config: { rateLimit: { max: 10, timeWindow: "1 minute" } } },
    async (req) => {
      const me = userIdOf(req);
      const body = explainBody.parse(req.body);
      if (!assistant) throw new AppError(503, "assistant_off", "Ask Sova isn't switched on yet.");

      let data: string;
      let task: string;
      if (body.topic === "dispute") {
        data = (await disputeData(body.disputeId!, me)).text;
        task = "Explain this dispute to me: what it is about, how it will be decided, and what I can do now.";
      } else if (body.topic === "circle") {
        data = await circleData(body.circleId!, me);
        task = "Explain this circle to me: how it works, where things stand this turn, and what I need to do next.";
      } else {
        data = body.circleId ? await circleData(body.circleId, me) : "No circle chosen.";
        task = `My question: ${body.question}`;
      }

      if (!daily.take(me)) {
        throw new AppError(429, "assistant_limit", "You've asked a lot today. Ask Sova will answer again tomorrow.");
      }

      const messages: ChatMessage[] = [
        { role: "system", content: systemPrompt(body.language) },
        { role: "user", content: `<data>\n${data}\n</data>\n\n${task}` },
      ];
      try {
        const text = await assistant.reply(messages);
        return { text, model: assistant.model, language: body.language };
      } catch (err) {
        if (!(err instanceof AssistantUnavailable)) throw err;
        req.log.warn({ reason: err.message }, "assistant: model service unavailable");
        throw new AppError(502, "assistant_unavailable", "Ask Sova couldn't answer just now. Please try again in a minute.");
      }
    },
  );
}
