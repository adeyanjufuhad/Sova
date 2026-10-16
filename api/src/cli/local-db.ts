/**
 * A local PostgreSQL 17 for development, with nothing to install: the same
 * embedded-postgres package the tests use. Data lives in api/.local-db
 * (git-ignored) and survives restarts. Stop it with Ctrl+C.
 *
 *   npm run db:local
 *
 * Then set DATABASE_URL in api/.env to the address it prints.
 */
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import EmbeddedPostgres from "embedded-postgres";
import pg from "pg";

const PORT = Number(process.env.LOCAL_DB_PORT ?? 5433);
const PASSWORD = "sova-local"; // local development only
const DATABASE = "sova";
const dir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../.local-db");

const server = new EmbeddedPostgres({
  databaseDir: dir,
  user: "postgres",
  password: PASSWORD,
  port: PORT,
  persistent: true,
  // UTF-8 like production; Windows would otherwise default to WIN1252 and reject "₦".
  initdbFlags: ["--encoding=UTF8", "--locale=C"],
  onLog: () => {},
});

if (!existsSync(path.join(dir, "PG_VERSION"))) {
  console.log("Creating a local PostgreSQL 17 in api/.local-db (first run only)...");
  await server.initialise();
}
await server.start();

const admin = new pg.Client({ host: "localhost", port: PORT, user: "postgres", password: PASSWORD, database: "postgres" });
await admin.connect();
const exists = await admin.query("select 1 from pg_database where datname = $1", [DATABASE]);
if (!exists.rowCount) await server.createDatabase(DATABASE);
await admin.end();

console.log(`PostgreSQL 17 is running. Put this in api/.env:

  DATABASE_URL=postgres://postgres:${PASSWORD}@localhost:${PORT}/${DATABASE}

Leave this window open; press Ctrl+C to stop.`);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, async () => {
    await server.stop();
    process.exit(0);
  });
}
