/**
 * Apply pending database migrations.
 *
 *   npm run migrate            (uses MIGRATION_DATABASE_URL, else DATABASE_URL)
 *
 * Run migrations as the database owner/admin, not as the restricted sova_app role.
 */
import { loadConfig } from "../config.js";
import { createPool } from "../db.js";
import { loadMigrations, migrate, resolveMigrationsDir } from "../migrate/runner.js";

const config = loadConfig({
  ...process.env,
  DATABASE_URL: process.env.MIGRATION_DATABASE_URL || process.env.DATABASE_URL,
});
const pool = createPool(config);
if (!pool) {
  console.error("Set MIGRATION_DATABASE_URL or DATABASE_URL to the database to migrate.");
  process.exit(1);
}

try {
  const dir = resolveMigrationsDir(process.env.MIGRATIONS_DIR);
  const applied = await migrate(pool, loadMigrations(dir), (m) => console.log(m));
  console.log(applied.length ? `Applied ${applied.length} migration(s).` : "Database is up to date.");
} catch (err) {
  console.error((err as Error).message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
