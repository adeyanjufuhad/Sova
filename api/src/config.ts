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
    // An empty value (as in a copied .env.example) means "not set".
    DATABASE_URL: z.string().url().optional().or(z.literal("").transform(() => undefined)),
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
    JWT_SECRET: z
      .string()
      .min(32, "JWT_SECRET must be at least 32 characters")
      .optional()
      .or(z.literal("").transform(() => undefined)),
    ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).max(86_400).default(900),
    REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(30),

    /** "test-numbers" (fixed codes for whitelisted phones) or "sms" (paid provider, not wired yet). */
    OTP_PROVIDER: z.enum(["test-numbers", "sms"]).default("test-numbers"),
    /** Whitelist for the test-numbers provider: "+2348000000001:123456,+2348000000002:654321". */
    OTP_TEST_NUMBERS: list,
    OTP_TTL_SECONDS: z.coerce.number().int().min(60).max(1_800).default(300),

    /**
     * Email sign-in codes: "off", "brevo" (sends through Brevo; needs BREVO_API_KEY
     * and a sender verified in Brevo) or "test-emails" (fixed codes, nothing sent).
     */
    EMAIL_PROVIDER: z.enum(["off", "brevo", "test-emails"]).default("off"),
    BREVO_API_KEY: z.string().trim().optional(),
    /** The verified sender, e.g. "Sova <you@gmail.com>" or just the address. */
    EMAIL_FROM: z.string().trim().optional(),
    /** Whitelist for the test-emails provider: "ada@example.com:123456,...". */
    OTP_TEST_EMAILS: list,

    /**
     * "Continue with Google": the OAuth client ids whose ID tokens are accepted
     * (web first; the web id is also what Android asks Google for). Empty = off.
     */
    GOOGLE_CLIENT_IDS: list,

    /** Enables POST /auth/demo, which signs into a private copy of the demo. */
    DEMO_LOGIN_ENABLED: bool,
    /** Private demo copies kept built in advance, so "Try the demo" is instant (0 = build on demand). */
    DEMO_SPARES: z.coerce.number().int().min(0).max(5).default(1),
    DEMO_PHONE: z
      .string()
      .regex(/^\+234[789][01]\d{8}$/)
      .default("+2348000000000"),

    /**
     * S3-compatible bucket for proof-of-payment photos (private: read through
     * short-lived signed links). Uploads are switched off until all are set.
     */
    S3_ENDPOINT: z.url().optional().or(z.literal("").transform(() => undefined)),
    S3_REGION: z.string().trim().default("auto"),
    S3_BUCKET: z.string().trim().optional(),
    S3_ACCESS_KEY_ID: z.string().trim().optional(),
    S3_SECRET_ACCESS_KEY: z.string().trim().optional(),

    /**
     * "Ask Sova": an OpenAI-compatible chat API (RumptyCloud AI inference).
     * Switched off until AI_API_KEY is set.
     */
    AI_BASE_URL: z.url().default("https://chat.rumptycloud.com/v1"),
    AI_API_KEY: z
      .string()
      .trim()
      .optional()
      .transform((v) => v || undefined),
    AI_MODEL: z.string().trim().min(1).default("llama3.2:3b"),
    AI_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(60_000).default(25_000),
    /** Answers each member can ask for per day (days in Lagos, counted in the database). */
    AI_DAILY_LIMIT: z.coerce.number().int().min(1).max(1_000).default(20),
    /** Answers the whole service gives per day, so the free inference allowance lasts. */
    AI_DAILY_TOTAL: z.coerce.number().int().min(1).max(100_000).default(60),
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
    if (c.EMAIL_PROVIDER === "brevo") {
      if (!c.BREVO_API_KEY) ctx.addIssue({ code: "custom", path: ["BREVO_API_KEY"], message: "is required when EMAIL_PROVIDER=brevo" });
      if (!c.EMAIL_FROM || !parseSender(c.EMAIL_FROM)) {
        ctx.addIssue({ code: "custom", path: ["EMAIL_FROM"], message: 'must be "Name <address>" or an address when EMAIL_PROVIDER=brevo' });
      }
    }
    for (const entry of c.OTP_TEST_EMAILS) {
      if (!/^[^@\s:]+@[^@\s:]+\.[^@\s:]+:\d{6}$/.test(entry)) {
        ctx.addIssue({ code: "custom", path: ["OTP_TEST_EMAILS"], message: "entries must look like ada@example.com:123456" });
      }
    }
  });

/** "Sova <you@example.com>" or "you@example.com" → the sender Brevo expects. */
export function parseSender(from: string): { email: string; name: string } | null {
  const m = /^\s*(?:(.+?)\s*<\s*([^<>\s]+@[^<>\s]+)\s*>|([^<>\s]+@[^<>\s]+))\s*$/.exec(from);
  if (!m) return null;
  return { email: (m[2] ?? m[3])!.toLowerCase(), name: m[1]?.trim() || "Sova" };
}

export type Config = z.infer<typeof schema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  ${i.path.join(".")}: ${i.message}`).join("\n");
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }
  return parsed.data;
}
