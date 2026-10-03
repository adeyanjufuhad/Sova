import { createHmac, randomInt, timingSafeEqual } from "node:crypto";

import type pg from "pg";

import { AppError } from "../lib/errors.js";

/**
 * Sends one-time codes. Providers decide which phones they can serve and what
 * the code is; the service stores only an HMAC of it.
 */
export interface OtpProvider {
  readonly name: string;
  /** The code to send to this phone, or an AppError if the phone can't be served. */
  codeFor(phone: string): string;
  send(phone: string, code: string): Promise<void>;
}

/**
 * Free provider for the beta and demos: only whitelisted phones can sign in,
 * each with a fixed code configured in OTP_TEST_NUMBERS. Nothing is sent.
 */
export class TestNumbersProvider implements OtpProvider {
  readonly name = "test-numbers";
  private readonly codes: Map<string, string>;

  constructor(entries: string[]) {
    this.codes = new Map(entries.map((e) => e.split(":") as [string, string]));
  }

  codeFor(phone: string): string {
    const code = this.codes.get(phone);
    if (!code) {
      throw new AppError(
        403,
        "phone_not_in_beta",
        "This number isn't part of the Sova beta yet. Use a test number, or try the demo.",
      );
    }
    return code;
  }

  async send(): Promise<void> {
    // Fixed codes: nothing to send.
  }
}

/**
 * Placeholder for a paid SMS gateway (e.g. Termii). Generates random codes;
 * sending is not wired up yet, so it fails clearly instead of pretending.
 */
export class SmsProvider implements OtpProvider {
  readonly name = "sms";

  codeFor(): string {
    return String(randomInt(0, 1_000_000)).padStart(6, "0");
  }

  async send(): Promise<void> {
    throw new AppError(503, "sms_not_configured", "SMS sign-in isn't available yet. Try the demo instead.");
  }
}

const MAX_REQUESTS_PER_WINDOW = 3;
const REQUEST_WINDOW_MINUTES = 10;
const MAX_VERIFY_ATTEMPTS = 5;

export class OtpService {
  constructor(
    private readonly pool: pg.Pool,
    private readonly provider: OtpProvider,
    private readonly secret: string,
    private readonly ttlSeconds: number,
  ) {}

  private hash(phone: string, code: string): string {
    return createHmac("sha256", this.secret).update(`${phone}:${code}`).digest("hex");
  }

  /** Creates a challenge and sends the code. Limited per phone, on top of per-IP limits. */
  async request(phone: string): Promise<{ expiresInSeconds: number; provider: string }> {
    const code = this.provider.codeFor(phone);
    const recent = await this.pool.query<{ n: number }>(
      `select count(*)::int as n from otp_challenges
        where phone = $1 and created_at > now() - make_interval(mins => $2)`,
      [phone, REQUEST_WINDOW_MINUTES],
    );
    if ((recent.rows[0]?.n ?? 0) >= MAX_REQUESTS_PER_WINDOW) {
      throw new AppError(429, "rate_limited", "Too many codes requested. Wait a few minutes and try again.");
    }
    await this.provider.send(phone, code);
    await this.pool.query(
      `insert into otp_challenges (phone, code_hash, expires_at)
       values ($1, $2, now() + make_interval(secs => $3))`,
      [phone, this.hash(phone, code), this.ttlSeconds],
    );
    return { expiresInSeconds: this.ttlSeconds, provider: this.provider.name };
  }

  /** Checks the latest live challenge for this phone. Five wrong tries burns it. */
  async verify(phone: string, code: string): Promise<void> {
    const { rows } = await this.pool.query<{ id: string; code_hash: string; attempts: number }>(
      `select id, code_hash, attempts from otp_challenges
        where phone = $1 and consumed_at is null and expires_at > now()
        order by created_at desc limit 1`,
      [phone],
    );
    const challenge = rows[0];
    if (!challenge) throw new AppError(400, "code_expired", "That code has expired. Request a new one.");
    if (challenge.attempts >= MAX_VERIFY_ATTEMPTS) {
      throw new AppError(429, "too_many_attempts", "Too many wrong codes. Request a new one.");
    }
    const expected = Buffer.from(challenge.code_hash, "hex");
    const actual = Buffer.from(this.hash(phone, code), "hex");
    if (!timingSafeEqual(expected, actual)) {
      await this.pool.query("update otp_challenges set attempts = attempts + 1 where id = $1", [challenge.id]);
      const left = MAX_VERIFY_ATTEMPTS - challenge.attempts - 1;
      throw new AppError(400, "wrong_code", `That code is not correct. ${left} ${left === 1 ? "try" : "tries"} left.`, {
        attemptsLeft: left,
      });
    }
    await this.pool.query("update otp_challenges set consumed_at = now() where id = $1", [challenge.id]);
  }
}
