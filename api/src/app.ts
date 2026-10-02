import Fastify, { type FastifyInstance } from "fastify";
import type pg from "pg";

import type { Config } from "./config.js";
import { healthRoutes } from "./routes/health.js";

export const VERSION = "0.1.0";

/**
 * Builds the Fastify app without starting it, so tests can inject requests.
 * Logs never include PINs, OTP codes, tokens or connection strings.
 */
export async function buildApp(config: Config, pool: pg.Pool | null): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: config.LOG_LEVEL,
      redact: {
        paths: [
          "req.headers.authorization",
          "req.headers.cookie",
          'res.headers["set-cookie"]',
          "*.pin",
          "*.newPin",
          "*.code",
          "*.otp",
          "*.token",
          "*.refreshToken",
          "*.accessToken",
          "*.password",
          "*.secret",
        ],
        censor: "[redacted]",
      },
    },
    // Behind the platform's load balancer.
    trustProxy: true,
    bodyLimit: 64 * 1024,
  });

  await app.register(healthRoutes, { pool, version: VERSION });

  return app;
}
