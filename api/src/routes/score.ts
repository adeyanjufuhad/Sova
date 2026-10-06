import { randomBytes } from "node:crypto";

import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";

import { requireUser, userIdOf } from "../auth/plugin.js";
import { verifyPin } from "../auth/pin.js";
import type { TokenService } from "../auth/tokens.js";
import { notFound } from "../lib/errors.js";

/**
 * The Sova Score: computed live by the database (sova_score_now, see
 * db/migrations/20261007000000_sova_score.sql). A member can publish a
 * snapshot behind a random link (share_sova_score); the public endpoint shows
 * only that snapshot, never phone numbers, circle names or amounts.
 */

const pinBody = z.object({ pin: z.string().regex(/^\d{4}$/, "Your PIN is 4 digits.") });
const tokenParam = z.object({ token: z.string().regex(/^[A-Za-z0-9_-]{22,64}$/, "Not a valid link.") });
const limited = { rateLimit: { max: 30, timeWindow: "1 minute" } };

/** Plain-words label for a score. It describes the record; it is not a credit rating. */
export const scoreBand = (score: number) =>
  score >= 90 ? "Excellent" : score >= 75 ? "Strong" : score >= 50 ? "Fair" : "Building";

const rate = (n: string | number) => Math.round(Number(n) * 1000) / 1000;

interface NowRow {
  score_value: number;
  on_time_rate: string;
  consistency_rate: string;
  completion_rate: string;
  active_cycles: number;
  completed_cycles: number;
  confirmed_payments: number;
  on_time_payments: number;
  turns_counted: number;
  min_payments: number;
}

interface ShareRow {
  token: string;
  display_name: string;
  score_value: number;
  on_time_rate: string;
  consistency_rate: string;
  completion_rate: string;
  confirmed_payments: number;
  completed_cycles: number;
  active_cycles: number;
  member_since: string;
  created_at: Date;
}

const shareView = (s: ShareRow) => ({
  token: s.token,
  displayName: s.display_name,
  score: s.score_value,
  band: scoreBand(s.score_value),
  onTimeRate: rate(s.on_time_rate),
  consistencyRate: rate(s.consistency_rate),
  completionRate: rate(s.completion_rate),
  confirmedPayments: s.confirmed_payments,
  completedCircles: s.completed_cycles,
  activeCircles: s.active_cycles,
  memberSince: s.member_since,
  sharedAt: s.created_at,
});

const SHARE_COLUMNS = `token, display_name, score_value, on_time_rate, consistency_rate, completion_rate,
  confirmed_payments, completed_cycles, active_cycles, member_since::text, created_at`;

export async function scoreRoutes(app: FastifyInstance, opts: { pool: pg.Pool; tokens: TokenService }) {
  const { pool } = opts;
  const auth = requireUser(opts.tokens);

  async function myScore(me: string) {
    const [now, share] = await Promise.all([
      pool.query<NowRow>("select *, sova_score_min_payments() as min_payments from sova_score_now($1)", [me]),
      pool.query<ShareRow>(`select ${SHARE_COLUMNS} from score_shares where user_id = $1 and revoked_at is null`, [me]),
    ]);
    const s = now.rows[0]!;
    const ready = s.confirmed_payments >= s.min_payments;
    return {
      /** Payments needed before a score is shown. */
      minimumPayments: s.min_payments,
      ready,
      score: ready ? s.score_value : null,
      band: ready ? scoreBand(s.score_value) : null,
      onTimeRate: rate(s.on_time_rate),
      consistencyRate: rate(s.consistency_rate),
      completionRate: rate(s.completion_rate),
      confirmedPayments: s.confirmed_payments,
      onTimePayments: s.on_time_payments,
      turnsCounted: s.turns_counted,
      activeCircles: s.active_cycles,
      completedCircles: s.completed_cycles,
      share: share.rows[0] ? shareView(share.rows[0]) : null,
    };
  }

  app.get("/me/score", { preHandler: auth }, async (req) => myScore(userIdOf(req)));

  /** Publishes a snapshot of the current score behind a new link (replacing any live one). */
  app.post("/me/score/share", { preHandler: auth, config: limited }, async (req, reply) => {
    const me = userIdOf(req);
    const { pin } = pinBody.parse(req.body);
    await verifyPin(pool, me, pin);
    const token = randomBytes(18).toString("base64url");
    await pool.query("select share_sova_score($1, $2)", [me, token]);
    return reply.code(201).send(await myScore(me));
  });

  /** Stops sharing: the link stops working straight away. */
  app.post("/me/score/share/stop", { preHandler: auth, config: limited }, async (req) => {
    const me = userIdOf(req);
    await pool.query("update score_shares set revoked_at = now() where user_id = $1 and revoked_at is null", [me]);
    return myScore(me);
  });

  /** What someone sees when they open a shared score link. No sign-in. */
  app.get("/public/scores/:token", { config: { rateLimit: { max: 60, timeWindow: "1 minute" } } }, async (req) => {
    const { token } = tokenParam.parse(req.params);
    const { rows } = await pool.query<ShareRow>(
      `select ${SHARE_COLUMNS} from score_shares where token = $1 and revoked_at is null`,
      [token],
    );
    if (!rows[0]) throw notFound("Shared score");
    const { token: _hidden, ...card } = shareView(rows[0]);
    return card;
  });
}
