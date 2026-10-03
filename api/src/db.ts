import pg from "pg";

import type { Config } from "./config.js";

type SslOption = pg.PoolConfig["ssl"];

/**
 * Resolves TLS settings. The `pg` driver treats sslmode=require as "verify the
 * certificate", unlike libpq. RumptyCloud's public endpoint has a self-signed
 * certificate, so we apply libpq semantics ourselves: require = encrypt only.
 */
export function resolveSsl(
  config: Pick<Config, "DATABASE_URL" | "DATABASE_SSL" | "DATABASE_CA_CERT">,
): { connectionString: string; ssl: SslOption } | null {
  if (!config.DATABASE_URL) return null;
  const url = new URL(config.DATABASE_URL);
  const sslmode = url.searchParams.get("sslmode");
  url.searchParams.delete("sslmode");

  let mode = config.DATABASE_SSL;
  if (mode === "auto") {
    if (sslmode === "verify-ca" || sslmode === "verify-full") mode = "verify";
    else if (sslmode === "require" || sslmode === "prefer") mode = "no-verify";
    else mode = "disable";
  }

  const ssl: SslOption =
    mode === "disable"
      ? false
      : mode === "verify"
        ? { rejectUnauthorized: true, ca: config.DATABASE_CA_CERT }
        : { rejectUnauthorized: false };

  return { connectionString: url.toString(), ssl };
}

/** Connection pool, created only when DATABASE_URL is configured. */
export function createPool(config: Pick<Config, "DATABASE_URL" | "DATABASE_SSL" | "DATABASE_CA_CERT">): pg.Pool | null {
  const resolved = resolveSsl(config);
  if (!resolved) return null;
  return new pg.Pool({
    ...resolved,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
  });
}
