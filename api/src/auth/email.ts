import { randomInt } from "node:crypto";

import { AppError } from "../lib/errors.js";
import type { OtpProvider } from "./otp.js";

/** Lower-cases and trims an email address; null if it doesn't look like one. */
export function normaliseEmail(input: string): string | null {
  const email = input.trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) && email.length <= 254 ? email : null;
}

/** Email codes are switched off until a sender is configured (EMAIL_PROVIDER). */
export class EmailOffProvider implements OtpProvider {
  readonly name = "off";

  codeFor(): string {
    throw new AppError(503, "email_not_configured", "Email sign-in isn't available yet. Try the demo instead.");
  }

  async send(): Promise<void> {}
}

/**
 * Fixed codes for whitelisted addresses (OTP_TEST_EMAILS), for tests and
 * local runs. Nothing is sent.
 */
export class TestEmailsProvider implements OtpProvider {
  readonly name = "test-emails";
  private readonly codes: Map<string, string>;

  constructor(entries: string[]) {
    this.codes = new Map(
      entries.map((e) => {
        const at = e.lastIndexOf(":");
        return [e.slice(0, at).trim().toLowerCase(), e.slice(at + 1).trim()] as [string, string];
      }),
    );
  }

  codeFor(email: string): string {
    const code = this.codes.get(email);
    if (!code) {
      throw new AppError(403, "email_not_in_beta", "This email isn't part of the Sova beta yet. Try the demo instead.");
    }
    return code;
  }

  async send(): Promise<void> {}
}

/**
 * Sends the code through Brevo's transactional email API (free tier: 300 a
 * day). The sender address must be verified in Brevo.
 */
export class BrevoEmailProvider implements OtpProvider {
  readonly name = "brevo";

  constructor(
    private readonly apiKey: string,
    private readonly from: { email: string; name: string },
    private readonly ttlMinutes: number,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  codeFor(): string {
    return String(randomInt(0, 1_000_000)).padStart(6, "0");
  }

  async send(to: string, code: string): Promise<void> {
    const text =
      `Your Sova sign-in code is ${code}. It expires in ${this.ttlMinutes} minutes.\n\n` +
      "If you didn't ask for it, ignore this email. Sova will never ask you for this code or your PIN.";
    const html =
      `<p>Your Sova sign-in code is</p><p style="font-size:28px;font-weight:700;letter-spacing:4px">${code}</p>` +
      `<p>It expires in ${this.ttlMinutes} minutes.</p>` +
      "<p>If you didn't ask for it, ignore this email. Sova will never ask you for this code or your PIN.</p>";
    let res: Response;
    try {
      res = await this.fetchImpl("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: { "api-key": this.apiKey, "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify({
          sender: this.from,
          to: [{ email: to }],
          subject: `${code} is your Sova sign-in code`,
          textContent: text,
          htmlContent: html,
        }),
        signal: AbortSignal.timeout(10_000),
      });
    } catch {
      throw new AppError(503, "email_unavailable", "We couldn't send the email just now. Please try again.");
    }
    if (!res.ok) {
      throw new AppError(503, "email_unavailable", "We couldn't send the email just now. Please try again.");
    }
  }
}
