import pg from "pg";

/** Connection pool, created only when DATABASE_URL is configured. */
export function createPool(databaseUrl: string | undefined): pg.Pool | null {
  if (!databaseUrl) return null;
  return new pg.Pool({
    connectionString: databaseUrl,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
  });
}
