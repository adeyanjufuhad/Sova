import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";

import { requireUser, userIdOf } from "../auth/plugin.js";
import type { TokenService } from "../auth/tokens.js";
import {
  AssistantUnavailable,
  SOVA_FACTS,
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
  payer_confirmed: "marked as sent, not confirmed yet",
  fully_confirmed: "paid and confirmed",
  disputed: "payment under dispute",
};

export interface AssistantLimits {
  /** Answers each member can have per day. */
  perMember: number;
  /** Answers the whole service gives per day, across everyone. */
  total: number;
}

/**
 * POST /assistant/explain: "Ask Sova" explains a circle, a dispute or a
 * question about how Sova works. Members only (404 otherwise, like every
 * circle route). The answer is a suggestion written by a model; the app labels
 * it as such and the circle screen stays the record.
 *
 * The API works out everything a small model tends to get wrong (who collects,
 * what you owe, what to do next, which disputes are open) and hands it over as
 * plain sentences, so the model only has to say it simply.
 */
export async function assistantRoutes(
  app: FastifyInstance,
  opts: { pool: pg.Pool; tokens: TokenService; assistant: Assistant | null; limits: AssistantLimits },
) {
  const { pool, assistant, limits } = opts;
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
      pool.query<{ id: string; kind: string; turn: number; payers: string[] }>(
        `select d.id, d.kind, r.round_number as turn,
                array(select u.full_name from dispute_payers(d.id) p(id) join users u on u.id = p.id) as payers
           from disputes d join rounds r on r.id = d.round_id
          where d.group_id = $1 and d.status = 'open' order by d.created_at`,
        [circleId],
      ),
    ]);

    // The person asking is "you" everywhere, so a small model doesn't mistake them for someone else.
    const nameOf = new Map(members.rows.map((m) => [m.id, m.id === me ? "YOU" : shortName(m.name)]));
    const payout = g.contribution_amount * (g.member_count - 1);
    const lines = [
      `Circle: ${g.name}. Status: ${g.status}.`,
      `Each member pays ${naira(g.contribution_amount)} each turn (${g.cycle_type}). ${members.rows.length} of ${g.member_count} members have joined.`,
      `Each turn one member collects ${naira(payout)}: one payment from each of the other ${g.member_count - 1} members. The collector keeps all of it; nothing is shared out or paid back.`,
      `Admin: ${nameOf.get(g.admin_id) ?? "a member"}${g.admin_collects_last ? " (promised to collect last)" : ""}.`,
    ];

    const r = rules.rows[0];
    if (r) {
      lines.push(
        `Rules: late fee ${naira(r.late_fee)} after ${r.grace_days} grace day(s); ${EXIT_POLICIES[r.early_exit_policy] ?? r.early_exit_policy}.` +
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
          const state = t?.status === "completed" ? "collected already" : t?.status === "active" ? "collecting now" : "waiting";
          return `${m.position}. ${nameOf.get(m.id)}: ${state}`;
        });
      lines.push(`Payout order (drawn fairly): ${order.join("; ")}.`);
    } else {
      lines.push(`Payout order: not drawn yet. It is drawn when all ${g.member_count} members have joined.`);
    }

    const current = rounds.rows.find((t) => t.status === "active");
    let statusOfMine: string | undefined;
    if (current) {
      const { rows: paid } = await pool.query<{ user_id: string; status: string }>(
        "select user_id, status from contributions where round_id = $1",
        [current.id],
      );
      const statusOf = new Map(paid.map((c) => [c.user_id, c.status]));
      statusOfMine = statusOf.get(me);
      const payments = members.rows
        .filter((m) => m.id !== current.collector_id)
        .map((m) => `${nameOf.get(m.id)}: ${CONTRIBUTION_STATES[statusOf.get(m.id) ?? ""] ?? "not paid yet"}`);
      lines.push(
        `This turn: turn ${current.number} of ${g.member_count}. Collector this turn: ${nameOf.get(current.collector_id)}, who receives ${naira(payout)} by ${dateInLagos(current.due_date)}. Each member collects only once in the circle.`,
        `Payments this turn: ${payments.join("; ")}.`,
      );
    }

    lines.push(
      disputes.rows.length
        ? `Open disputes: ${disputes.rows
            .map((d) =>
              d.kind === "shortfall"
                ? `the turn ${d.turn} payout was short`
                : `about ${d.payers.map(shortName).join(", ")}'s payment for turn ${d.turn}`,
            )
            .join("; ")}.`
        : "Open disputes: none.",
    );

    // The member's own position and next step, worked out here rather than by the model.
    const mine = members.rows.find((m) => m.id === me);
    const myTurn = byCollector.get(me);
    lines.push(
      "YOU = the member asking." +
        (mine?.position ? ` You are number ${mine.position} in the payout order.` : "") +
        (myTurn?.status === "completed" ? " You have already collected." : ""),
      `What you should do now: ${nextStep(g, current, statusOfMine, me, nameOf)}`,
    );
    return lines.join("\n");
  }

  function nextStep(
    g: { status: string; contribution_amount: number; member_count: number },
    current: { collector_id: string } | undefined,
    mine: string | undefined,
    me: string,
    nameOf: Map<string, string>,
  ): string {
    if (g.status === "forming") return "wait for the circle to fill up; share the invite code with people you trust.";
    if (g.status === "completed") return "nothing: every turn has been paid out.";
    if (g.status === "cancelled") return "nothing: the circle was cancelled before it started.";
    if (!current) return "nothing right now.";
    if (current.collector_id === me) {
      return "you are collecting this turn: check your bank for each payment and confirm it in the app with your PIN, then confirm the payout.";
    }
    const collector = nameOf.get(current.collector_id);
    switch (mine) {
      case "payer_confirmed":
        return `wait for ${collector} to confirm your payment.`;
      case "fully_confirmed":
        return "nothing: your payment this turn is confirmed.";
      case "disputed":
        return "your payment is under dispute; open the dispute to see the vote.";
      default:
        return `you have not paid this turn. Send ${naira(g.contribution_amount)} to ${collector} by bank transfer or cash, then tap Pay in the app and enter your PIN.`;
    }
  }

  async function disputeData(disputeId: string, me: string): Promise<string> {
    const { rows } = await pool.query<{
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
      `select g.name as circle_name, d.kind, d.status, d.reason, r.round_number as turn,
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
    const needed = Math.floor(voters / 2) + 1;
    const payerNames = payers.rows.map((p) => shortName(p.name)).join(", ") || "none";
    const isCollector = d.collector_id === me;
    const isPayer = payers.rows.some((p) => p.id === me);
    const open = d.status === "open";

    const lines = [`Circle: ${d.circle_name}. This dispute is ${d.status}.`];
    if (d.kind === "shortfall") {
      lines.push(
        `What it is about: the turn ${d.turn} payout to ${shortName(d.collector_name)} was short. Members who had not paid: ${payerNames}.`,
        "How it ends: there is no vote. It closes when every missing payment is confirmed, or the collector marks it settled.",
      );
    } else {
      lines.push(
        `What it is about: ${payerNames} says they paid ${naira(d.amount ?? d.contribution_amount)} for turn ${d.turn} to the collector ${shortName(d.collector_name)}. Raised by ${shortName(d.raised_by_name)}. The payment is frozen until this is decided.`,
        `How it ends: the other members vote "it arrived" or "it didn't arrive". ${voters} members can vote and ${needed} votes decide. So far ${count("payer")} say it arrived and ${count("collector")} say it didn't. Either side can also settle by agreeing with the other. "It arrived" confirms the payment; "it didn't arrive" puts it back to unpaid.`,
      );
    }
    if (d.reason) lines.push(`Reason given: ${d.reason.slice(0, 500)}`);

    const role = isCollector ? "the collector" : isPayer ? "the payer" : "a voter";
    const todo = !open
      ? "nothing: it is closed."
      : d.kind === "shortfall"
        ? isCollector
          ? "confirm each missing payment when it arrives, or mark the dispute settled."
          : isPayer
            ? "pay what is missing and record it in the app."
            : "nothing; there is no vote on a short payout."
        : isCollector || isPayer
          ? "add evidence or a comment, or settle by agreeing with the other side. You cannot vote."
          : "look at the evidence and vote with your PIN.";
    lines.push(`YOU = the member asking. You are ${role} in this dispute. What you can do: ${todo}`);
    return lines.join("\n");
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
        data = await disputeData(body.disputeId!, me);
        task = "Explain this dispute to me: what it is about, how it will be decided, and what I can do now.";
      } else if (body.topic === "circle") {
        data = await circleData(body.circleId!, me);
        task = "Explain this circle to me: how it works, where things stand this turn, and what I should do now.";
      } else {
        data = SOVA_FACTS + (body.circleId ? `\n\n${await circleData(body.circleId, me)}` : "");
        task = `Answer my question using the facts above. My question: ${body.question}`;
      }

      const { rows } = await pool.query<{ result: string }>("select take_assistant_answer($1, $2, $3) as result", [
        me,
        limits.perMember,
        limits.total,
      ]);
      if (rows[0]!.result === "member_limit") {
        throw new AppError(429, "assistant_limit", "You've asked a lot today. Ask Sova will answer again tomorrow.");
      }
      if (rows[0]!.result === "total_limit") {
        throw new AppError(429, "assistant_busy", "Ask Sova has answered all it can for today. It will be back tomorrow.");
      }

      const messages: ChatMessage[] = [
        { role: "system", content: systemPrompt(body.language) },
        { role: "user", content: `<data>\n${data}\n</data>\n\n${task}` },
      ];
      try {
        const text = await assistant.reply(messages);
        return { text, model: assistant.model, language: body.language };
      } catch (err) {
        await pool.query("select give_back_assistant_answer($1)", [me]);
        if (!(err instanceof AssistantUnavailable)) throw err;
        req.log.warn({ reason: err.message }, "assistant: model service unavailable");
        throw new AppError(502, "assistant_unavailable", "Ask Sova couldn't answer just now. Please try again in a minute.");
      }
    },
  );
}
