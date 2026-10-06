import { randomBytes } from "node:crypto";

import cors from "@fastify/cors";
import rateLimit from "@fastify/rate-limit";
import Fastify, { type FastifyInstance } from "fastify";
import type pg from "pg";

import { OtpService, SmsProvider, TestNumbersProvider, type OtpProvider } from "./auth/otp.js";
import { TokenService } from "./auth/tokens.js";
import type { Config } from "./config.js";
import { AppError, registerErrorHandler } from "./lib/errors.js";
import { createProofStorage, type ProofStorage } from "./lib/storage.js";
import { authRoutes } from "./routes/auth.js";
import { circleRoutes } from "./routes/circles.js";
import { healthRoutes } from "./routes/health.js";
import { ledgerRoutes } from "./routes/ledger.js";
import { waitlistRoutes } from "./routes/waitlist.js";

export const VERSION = "0.4.0";

export interface AppOverrides {
  otpProvider?: OtpProvider;
  /** Replaces the S3 bucket (tests). */
  storage?: ProofStorage | null;
}

/**
 * Builds the Fastify app without starting it, so tests can inject requests.
 * Logs never include PINs, OTP codes, tokens or connection strings.
 */
export async function buildApp(config: Config, pool: pg.Pool | null, overrides: AppOverrides = {}): Promise<FastifyInstance> {
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
    // Behind the platform's load balancer: use the client IP for rate limits.
    trustProxy: true,
    bodyLimit: 64 * 1024,
  });

  registerErrorHandler(app);

  await app.register(cors, {
    origin: config.CORS_ORIGINS.length ? config.CORS_ORIGINS : false,
    methods: ["GET", "POST", "PATCH", "PUT", "DELETE"],
    allowedHeaders: ["Authorization", "Content-Type"],
    maxAge: 600,
  });
  await app.register(rateLimit, { global: false });

  await app.register(healthRoutes, { pool, version: VERSION });

  if (!pool) {
    // Without a database only /health works; everything else explains why.
    app.addHook("onRequest", async (req) => {
      if (req.url !== "/health") throw new AppError(503, "database_not_configured", "The database is not configured.");
    });
    return app;
  }

  let secret = config.JWT_SECRET;
  if (!secret) {
    secret = randomBytes(32).toString("hex");
    app.log.warn("JWT_SECRET is not set: using a random secret; sessions end when the server restarts");
  }

  const provider =
    overrides.otpProvider ??
    (config.OTP_PROVIDER === "sms" ? new SmsProvider() : new TestNumbersProvider(config.OTP_TEST_NUMBERS));
  const otp = new OtpService(pool, provider, secret, config.OTP_TTL_SECONDS);
  const tokens = new TokenService(pool, secret, config.ACCESS_TOKEN_TTL_SECONDS, config.REFRESH_TOKEN_TTL_DAYS);

  await app.register(authRoutes, {
    pool,
    otp,
    tokens,
    demoEnabled: config.DEMO_LOGIN_ENABLED,
    demoPhone: config.DEMO_PHONE,
  });
  const storage = overrides.storage !== undefined ? overrides.storage : createProofStorage(config);
  await app.register(circleRoutes, { pool, tokens, storage });
  await app.register(waitlistRoutes, { pool });
  await app.register(ledgerRoutes, { pool });

  return app;
}
