import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import type pg from "pg";

/** Restricted role the API connects as in production (see `npm run db:create-app-role`). */
export const APP_ROLE = "sova_app";

const here = path.dirname(fileURLToPath(import.meta.url));

/**
 * Where the SQL files live: MIGRATIONS_DIR if set, else the copy made at build
 * time (dist/migrations), else the repository's db/migrations.
 */
export function resolveMigrationsDir(override?: string): string {
  const candidates = [override, path.resolve(here, "../migrations"), path.resolve(here, "../../../db/migrations")];
  for (const dir of candidates) {
    if (dir && existsSync(dir)) return dir;
  }
  throw new Error(`No migrations directory found (looked in: ${candidates.filter(Boolean).join(", ")})`);
}

export interface Migration {
  version: string;
  sql: string;
  checksum: string;
}

export function loadMigrations(dir: string): Migration[] {
  return readdirSync(dir)
    .filter((f) => /^\d{14}_[a-z0-9_]+\.sql$/.test(f))
    .sort()
    .map((file) => {
      const sql = readFileSync(path.join(dir, file), "utf8").replace(/\r\n/g, "\n");
      return {
        version: file.replace(/\.sql$/, ""),
        sql,
        checksum: createHash("sha256").update(sql).digest("hex"),
      };
    });
}

/**
 * Applies pending migrations in order, each in its own transaction, under an
 * advisory lock so concurrent deploys cannot race. A migration that changed
 * after being applied is an error: migrations are immutable, add a new one.
 * Returns the versions applied in this run.
 */
export async function migrate(
  pool: pg.Pool,
  migrations: Migration[],
  log: (msg: string) => void = () => {},
): Promise<string[]> {
  const client = await pool.connect();
  const applied: string[] = [];
  try {
    await client.query("select pg_advisory_lock(hashtext('sova_migrations'))");
    await client.query(`
      create table if not exists schema_migrations (
        version     text primary key,
        checksum    text not null,
        applied_at  timestamptz not null default now()
      )`);
    const { rows } = await client.query<{ version: string; checksum: string }>(
      "select version, checksum from schema_migrations",
    );
    const done = new Map(rows.map((r) => [r.version, r.checksum]));

    for (const m of migrations) {
      const previous = done.get(m.version);
      if (previous) {
        if (previous !== m.checksum) {
          throw new Error(`Migration ${m.version} changed after it was applied. Add a new migration instead.`);
        }
        continue;
      }
      log(`applying ${m.version}`);
      await client.query("begin");
      try {
        await client.query(m.sql);
        await client.query("insert into schema_migrations (version, checksum) values ($1, $2)", [m.version, m.checksum]);
        await client.query("commit");
      } catch (err) {
        await client.query("rollback");
        throw new Error(`Migration ${m.version} failed: ${(err as Error).message}`);
      }
      applied.push(m.version);
    }

    await grantAppRole(client);
    return applied;
  } finally {
    await client.query("select pg_advisory_unlock(hashtext('sova_migrations'))").catch(() => {});
    client.release();
  }
}

/**
 * Gives the restricted API role access to everything the migrations created.
 * Runs after every migration, so new tables are covered. Tables that must stay
 * append-only (the ledger) revoke UPDATE/DELETE from this role in their own
 * migration and enforce it with triggers as well.
 */
export async function grantAppRole(client: pg.PoolClient): Promise<void> {
  const { rowCount } = await client.query("select 1 from pg_roles where rolname = $1", [APP_ROLE]);
  if (!rowCount) return;
  await client.query(`grant usage on schema public to ${APP_ROLE}`);
  await client.query(`grant select, insert, update, delete on all tables in schema public to ${APP_ROLE}`);
  await client.query(`grant usage, select on all sequences in schema public to ${APP_ROLE}`);
  await client.query(`grant execute on all functions in schema public to ${APP_ROLE}`);
  await client.query(`revoke all on schema_migrations from ${APP_ROLE}`);
  await client.query(`grant select on schema_migrations to ${APP_ROLE}`);
  // Tables listed in append_only_tables (created by later migrations) lose UPDATE/DELETE.
  const { rows } = await client.query<{ exists: boolean }>(
    "select to_regclass('public.append_only_tables') is not null as exists",
  );
  if (rows[0]?.exists) {
    const t = await client.query<{ name: string }>("select name from append_only_tables");
    for (const { name } of t.rows) {
      await client.query(`revoke update, delete, truncate on ${client.escapeIdentifier(name)} from ${APP_ROLE}`);
    }
  }
}
