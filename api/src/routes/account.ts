import type { FastifyInstance } from "fastify";
import type pg from "pg";
import { z } from "zod";

import { requireUser, userIdOf } from "../auth/plugin.js";
import { verifyPin } from "../auth/pin.js";
import type { TokenService } from "../auth/tokens.js";
import type { ProofStorage } from "../lib/storage.js";

const deleteBody = z.object({ pin: z.string().regex(/^\d{4}$/, "Your PIN is 4 digits.") });

/**
 * Deleting your own account. The rules (only when no circle of yours is still
 * running; circles still forming are left; the shared demo account refuses)
 * live in delete_account, see db/migrations/20261010000000_leave_cancel_delete.sql.
 */
export async function accountRoutes(
  app: FastifyInstance,
  opts: { pool: pg.Pool; tokens: TokenService; storage: ProofStorage | null },
) {
  const { pool, storage } = opts;

  app.post(
    "/me/delete",
    { preHandler: requireUser(opts.tokens), config: { rateLimit: { max: 5, timeWindow: "1 minute" } } },
    async (req, reply) => {
      const me = userIdOf(req);
      const { pin } = deleteBody.parse(req.body);
      await verifyPin(pool, me, pin);
      const { rows: photos } = await pool.query<{ proof_url: string }>(
        "select proof_url from contributions where user_id = $1 and proof_url is not null",
        [me],
      );
      await pool.query("select delete_account($1)", [me]);

      // The account is gone either way; a photo that fails to delete is logged (by key only) to remove by hand.
      if (storage) {
        for (const { proof_url: key } of photos) {
          try {
            await storage.remove(key);
          } catch (err) {
            req.log.error({ err, key }, "account deletion: receipt photo not removed");
          }
        }
      }
      return reply.code(204).send();
    },
  );
}
