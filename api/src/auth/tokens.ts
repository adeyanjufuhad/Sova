import { createHash, randomBytes, randomUUID } from "node:crypto";

import { SignJWT, jwtVerify } from "jose";
import type pg from "pg";

import { AppError } from "../lib/errors.js";

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  /** Seconds until the access token expires. */
  expiresIn: number;
}

const sha256 = (s: string) => createHash("sha256").update(s).digest("hex");

/**
 * Short-lived JWT access tokens plus opaque refresh tokens stored as SHA-256
 * hashes. Refresh tokens rotate on every use; reusing a rotated token revokes
 * the whole family, because it means the token was copied.
 */
export class TokenService {
  private readonly key: Uint8Array;

  constructor(
    private readonly pool: pg.Pool,
    secret: string,
    private readonly accessTtlSeconds: number,
    private readonly refreshTtlDays: number,
  ) {
    this.key = new TextEncoder().encode(secret);
  }

  async signAccess(userId: string): Promise<string> {
    return new SignJWT({})
      .setProtectedHeader({ alg: "HS256" })
      .setSubject(userId)
      .setIssuedAt()
      .setIssuer("sova-api")
      .setExpirationTime(`${this.accessTtlSeconds}s`)
      .sign(this.key);
  }

  /** Returns the user id, or throws 401. */
  async verifyAccess(token: string): Promise<string> {
    try {
      const { payload } = await jwtVerify(token, this.key, { issuer: "sova-api", algorithms: ["HS256"] });
      if (!payload.sub) throw new Error("no subject");
      return payload.sub;
    } catch {
      throw new AppError(401, "unauthorized", "Your session has expired. Please sign in again.");
    }
  }

  private async newRefresh(userId: string, familyId: string, userAgent?: string) {
    const token = randomBytes(32).toString("base64url");
    const { rows } = await this.pool.query<{ id: string }>(
      `insert into sessions (user_id, family_id, token_hash, expires_at, user_agent)
       values ($1, $2, $3, now() + make_interval(days => $4), $5) returning id`,
      [userId, familyId, sha256(token), this.refreshTtlDays, userAgent?.slice(0, 300) ?? null],
    );
    return { token, id: rows[0]!.id };
  }

  async issue(userId: string, userAgent?: string): Promise<TokenPair> {
    const refresh = await this.newRefresh(userId, randomUUID(), userAgent);
    return { accessToken: await this.signAccess(userId), refreshToken: refresh.token, expiresIn: this.accessTtlSeconds };
  }

  /** Exchanges a refresh token for a new pair; detects reuse of rotated tokens. */
  async rotate(refreshToken: string, userAgent?: string): Promise<{ userId: string; tokens: TokenPair }> {
    const client = await this.pool.connect();
    try {
      await client.query("begin");
      const { rows } = await client.query<{
        id: string;
        user_id: string;
        family_id: string;
        expires_at: Date;
        revoked_at: Date | null;
      }>("select id, user_id, family_id, expires_at, revoked_at from sessions where token_hash = $1 for update", [
        sha256(refreshToken),
      ]);
      const s = rows[0];
      const invalid = new AppError(401, "unauthorized", "Your session has expired. Please sign in again.");
      if (!s) {
        await client.query("rollback");
        throw invalid;
      }
      if (s.revoked_at) {
        // A rotated token came back: assume theft and end every session in the chain.
        await client.query("update sessions set revoked_at = now() where family_id = $1 and revoked_at is null", [
          s.family_id,
        ]);
        await client.query("commit");
        throw invalid;
      }
      if (s.expires_at.getTime() <= Date.now()) {
        await client.query("rollback");
        throw invalid;
      }
      const token = randomBytes(32).toString("base64url");
      const next = await client.query<{ id: string }>(
        `insert into sessions (user_id, family_id, token_hash, expires_at, user_agent)
         values ($1, $2, $3, now() + make_interval(days => $4), $5) returning id`,
        [s.user_id, s.family_id, sha256(token), this.refreshTtlDays, userAgent?.slice(0, 300) ?? null],
      );
      await client.query("update sessions set revoked_at = now(), replaced_by = $2 where id = $1", [s.id, next.rows[0]!.id]);
      await client.query("commit");
      return {
        userId: s.user_id,
        tokens: { accessToken: await this.signAccess(s.user_id), refreshToken: token, expiresIn: this.accessTtlSeconds },
      };
    } catch (err) {
      await client.query("rollback").catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  /** Signs out: revokes the token's whole family. Unknown tokens are ignored. */
  async revoke(refreshToken: string): Promise<void> {
    await this.pool.query(
      `update sessions set revoked_at = now()
        where revoked_at is null
          and family_id = (select family_id from sessions where token_hash = $1)`,
      [sha256(refreshToken)],
    );
  }
}
