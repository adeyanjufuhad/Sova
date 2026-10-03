/**
 * Creates (or rotates the password of) the restricted `sova_app` role the API
 * should connect as in production, and grants it access to the schema.
 *
 *   npm run db:create-app-role      (uses MIGRATION_DATABASE_URL, else DATABASE_URL, as admin)
 *
 * The new connection string is printed once to this terminal for you to paste
 * into the deployment's DATABASE_URL. It is not stored or logged anywhere.
 */
import { randomBytes } from "node:crypto";

import { loadConfig } from "../config.js";
import { createPool } from "../db.js";
import { APP_ROLE, grantAppRole } from "../migrate/runner.js";

const adminUrl = process.env.MIGRATION_DATABASE_URL || process.env.DATABASE_URL;
const pool = createPool(loadConfig({ ...process.env, DATABASE_URL: adminUrl }));
if (!pool || !adminUrl) {
  console.error("Set MIGRATION_DATABASE_URL or DATABASE_URL to the admin connection string.");
  process.exit(1);
}

const client = await pool.connect();
try {
  const password = randomBytes(24).toString("base64url");
  const exists = (await client.query("select 1 from pg_roles where rolname = $1", [APP_ROLE])).rowCount;
  const verb = exists ? "alter" : "create";
  // Role names and passwords can't be bind parameters; the password is escaped as a literal.
  await client.query(`${verb} role ${APP_ROLE} with login nosuperuser nocreatedb nocreaterole password ${client.escapeLiteral(password)}`);
  const db = (await client.query<{ db: string }>("select current_database() as db")).rows[0]!.db;
  await client.query(`grant connect on database ${client.escapeIdentifier(db)} to ${APP_ROLE}`);
  await grantAppRole(client);

  const url = new URL(adminUrl);
  url.username = APP_ROLE;
  url.password = password;
  console.log(`${exists ? "Rotated password for" : "Created"} role ${APP_ROLE}.`);
  console.log("\nConnection string for the API (shown once; paste it into the deployment, then clear this terminal):\n");
  console.log(`  ${url.toString()}\n`);
  console.log("On RumptyCloud, use the same user and password with the database's INTERNAL host.");
} finally {
  client.release();
  await pool.end();
}
