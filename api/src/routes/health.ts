import type { FastifyInstance } from "fastify";
import type pg from "pg";

type DatabaseStatus = "ok" | "unavailable" | "not_configured";

/**
 * GET /health: liveness and readiness in one. Returns 200 when the API is up
 * and the database (if configured) answers; 503 when the database is
 * configured but unreachable, so the platform can restart or hold traffic.
 */
export async function healthRoutes(app: FastifyInstance, opts: { pool: pg.Pool | null; version: string }) {
  app.get("/health", async (_req, reply) => {
    let database: DatabaseStatus = "not_configured";
    if (opts.pool) {
      try {
        await opts.pool.query("select 1");
        database = "ok";
      } catch (err) {
        app.log.warn({ err }, "health check: database unreachable");
        database = "unavailable";
      }
    }
    const healthy = database !== "unavailable";
    return reply.code(healthy ? 200 : 503).send({
      status: healthy ? "ok" : "degraded",
      version: opts.version,
      uptimeSeconds: Math.round(process.uptime()),
      database,
    });
  });
}
