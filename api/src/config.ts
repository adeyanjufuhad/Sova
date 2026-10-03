import { z } from "zod";

/**
 * All configuration comes from environment variables, validated once at
 * startup so a misconfigured deployment fails fast with a clear message.
 * Every variable is documented in .env.example.
 */

const bool = z
  .enum(["true", "false", "1", "0", ""])
  .optional()
  .transform((v) => v === "true" || v === "1");

const list = z
  .string()
  .default("")
  .transform((v) =>
    v
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  );

const schema = z
  .object({
    NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
    HOST: z.string().default("0.0.0.0"),
    PORT: z.coerce.number().int().min(1).max(65535).default(8080),
    LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),

    /** Postgres connection string. Optional until the database is attached. */
    DATABASE_URL: z.string().url().optional(),
    /**
     * TLS to Postgres. "auto" follows the URL's sslmode (require/prefer encrypt without
     * verifying, verify-ca/verify-full verify, otherwise off). RumptyCloud's public
     * endpoint uses a self-signed certificate, so "require" there means encrypt only.
     */
    DATABASE_SSL: z.enum(["auto", "disable", "no-verify", "verify"]).default("auto"),
    /** PEM certificate to verify the database server, when DATABASE_SSL=verify. */
    DATABASE_CA_CERT: z.string().optional(),
    /** Apply pending migrations when the server starts (single instance deployments). */
    RUN_MIGRATIONS_ON_START: bool,

    /** Browser origins allowed to call the API, comma-separated. */
    CORS_ORIGINS: list,

    /** Secret for signing access tokens and hashing OTP codes. At least 32 characters. */
    JWT_SECRET: z.string().min(32, "JWT_SECRET must be at least 32 characters").optional(),
    ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).max(86_400).default(900),
    REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(30),

    /** "test-numbers" (fixed codes for whitelisted phones) or "sms" (paid provider, not wired yet). */
    OTP_PROVIDER: z.enum(["test-numbers", "sms"]).default("test-numbers"),
    /** Whitelist for the test-numbers provider: "+2348000000001:123456,+2348000000002:654321". */
    OTP_TEST_NUMBERS: list,
    OTP_TTL_SECONDS: z.coerce.number().int().min(60).max(1_800).default(300),

    /** Enables POST /auth/demo, which signs into the seeded demo account. */
    DEMO_LOGIN_ENABLED: bool,
    DEMO_PHONE: z
      .string()
      .regex(/^\+234[789][01]\d{8}$/)
      .default("+2348000000000"),
  })
  .superRefine((c, ctx) => {
    if (c.NODE_ENV === "production" && !c.JWT_SECRET) {
      ctx.addIssue({ code: "custom", path: ["JWT_SECRET"], message: "is required in production" });
    }
    if (c.DATABASE_SSL === "verify" && !c.DATABASE_CA_CERT) {
      ctx.addIssue({ code: "custom", path: ["DATABASE_CA_CERT"], message: "is required when DATABASE_SSL=verify" });
    }
    for (const entry of c.OTP_TEST_NUMBERS) {
      if (!/^\+234[789][01]\d{8}:\d{6}$/.test(entry)) {
        ctx.addIssue({
          code: "custom",
          path: ["OTP_TEST_NUMBERS"],
          message: `entries must look like +2348000000001:123456 (got "${entry.split(":")[0]}:…")`,
        });
      }
    }
  });

export type Config = z.infer<typeof schema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  ${i.path.join(".")}: ${i.message}`).join("\n");
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }
  return parsed.data;
}
