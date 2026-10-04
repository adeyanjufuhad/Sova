import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";

import { notFound } from "../lib/errors.js";

const params = z.object({ id: z.uuid("Not a valid circle id.") });

/**
 * Public, read-only view of a circle's ledger for the "Verify this circle"
 * page. No sign-in: anyone with the circle's link can check its record.
 * Entries hold first names and initials, amounts and dates; never phone
 * numbers or bank details.
 */
export async function ledgerRoutes(app: FastifyInstance, opts: { pool: pg.Pool }) {
  /** The seeded demo circles (reserved demo numbers only), so anyone can try the verify page. */
  app.get("/public/demo-circles", async () => {
    const { rows } = await opts.pool.query<{ id: string; name: string; status: string }>(
      `select g.id, g.name, g.status from groups g join users u on u.id = g.admin_id
        where u.phone like '+2348000000%' order by g.name`,
    );
    return { circles: rows };
  });

  app.get("/public/circles/:id/ledger", { config: { rateLimit: { max: 60, timeWindow: "1 minute" } } }, async (req) => {
    const { id } = params.parse(req.params);
    const circle = await opts.pool.query<{ name: string; status: string; member_count: number }>(
      "select name, status, member_count from groups where id = $1",
      [id],
    );
    if (!circle.rows[0]) throw notFound("Circle");
    const { rows } = await opts.pool.query<{ seq: number; kind: string; body: string; prev_hash: string; hash: string }>(
      "select seq, kind, body, prev_hash, hash from ledger_entries where group_id = $1 order by seq",
      [id],
    );
    const c = circle.rows[0];
    return {
      circle: { id, name: c.name, status: c.status, memberCount: c.member_count },
      hashRule: 'SHA-256(prevHash + "|" + seq + "|" + kind + "|" + body); the first prevHash is 64 zeros',
      head: rows.length ? { seq: rows[rows.length - 1]!.seq, hash: rows[rows.length - 1]!.hash } : null,
      entries: rows.map((r) => ({ seq: r.seq, kind: r.kind, body: r.body, prevHash: r.prev_hash, hash: r.hash })),
    };
  });
}
