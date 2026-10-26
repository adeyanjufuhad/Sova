import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";

import { AppError } from "../lib/errors.js";

export interface GoogleIdentity {
  /** Google's stable account id (`sub`). */
  sub: string;
  /** Lower-cased; Google has verified it. */
  email: string;
  name: string | null;
}

/** Checks a Google ID token and returns who signed in. */
export interface GoogleVerifier {
  verify(idToken: string): Promise<GoogleIdentity>;
}

const invalid = () => new AppError(401, "google_invalid", "Google sign-in didn't work. Please try again.");

/**
 * Verifies ID tokens from "Sign in with Google" against Google's published
 * keys: signature, issuer, expiry, and that the audience is one of Sova's own
 * OAuth client ids (GOOGLE_CLIENT_IDS). No client secret is needed.
 */
export class GoogleIdTokenVerifier implements GoogleVerifier {
  constructor(
    private readonly clientIds: string[],
    private readonly keys: JWTVerifyGetKey = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs")),
  ) {}

  async verify(idToken: string): Promise<GoogleIdentity> {
    let payload;
    try {
      ({ payload } = await jwtVerify(idToken, this.keys, {
        issuer: ["https://accounts.google.com", "accounts.google.com"],
        audience: this.clientIds,
      }));
    } catch {
      throw invalid();
    }
    const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : "";
    if (!payload.sub || !email || payload.email_verified !== true) throw invalid();
    return { sub: payload.sub, email, name: typeof payload.name === "string" ? payload.name.trim() || null : null };
  }
}

/** Used when GOOGLE_CLIENT_IDS is empty: Google sign-in is off. */
export class GoogleOffVerifier implements GoogleVerifier {
  async verify(): Promise<GoogleIdentity> {
    throw new AppError(503, "google_not_configured", "Google sign-in isn't available yet. Try the demo instead.");
  }
}
