import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";

import { normalisePhone } from "../lib/phone.js";

const body = z.object({
  name: z.string().trim().min(2, "Please enter your name.").max(80),
  phone: z
    .string()
    .max(30)
    .transform((v, ctx) => {
      const phone = normalisePhone(v);
      if (!phone) {
        ctx.addIssue({ code: "custom", message: "Please enter a valid Nigerian phone number." });
        return z.NEVER;
      }
      return phone;
    }),
  role: z.enum(["member", "admin", "collector"], { error: "Please choose what describes you." }),
  city: z.string().trim().max(80).nullish(),
  groupSize: z.coerce.number().int().min(1).max(5000).nullish().catch(null),
  /** Honeypot: people never fill it in; bots do. */
  website: z.string().max(200).nullish(),
});

/** The website's "Join the waitlist" form. */
export async function waitlistRoutes(app: FastifyInstance, opts: { pool: pg.Pool }) {
  app.post("/waitlist", { config: { rateLimit: { max: 5, timeWindow: "1 minute" } } }, async (req, reply) => {
    const input = body.parse(req.body);
    // Pretend success so bots move on.
    if (input.website) return reply.code(201).send({ ok: true });
    // Signing up twice with the same number counts as success.
    await opts.pool.query(
      `insert into waitlist (name, phone, role, city, group_size) values ($1, $2, $3, $4, $5)
       on conflict (phone) do nothing`,
      [input.name, input.phone, input.role, input.city || null, input.groupSize ?? null],
    );
    return reply.code(201).send({ ok: true });
  });
}
