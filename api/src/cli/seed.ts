/**
 * Recreate the demo data (people in the reserved +2348000000xxx range and
 * their circles). Safe to re-run; real users are never touched.
 *
 *   npm run seed       (uses MIGRATION_DATABASE_URL, else DATABASE_URL)
 */
import { loadConfig } from "../config.js";
import { createPool } from "../db.js";
import { DEMO_PHONE, DEMO_PIN, seedDemo } from "../seed/demo.js";

const pool = createPool(
  loadConfig({ ...process.env, DATABASE_URL: process.env.MIGRATION_DATABASE_URL || process.env.DATABASE_URL }),
);
if (!pool) {
  console.error("Set MIGRATION_DATABASE_URL or DATABASE_URL to the database to seed.");
  process.exit(1);
}

try {
  const { circles, people } = await seedDemo(pool);
  console.log(`Seeded ${people} people and ${circles} circles.`);
  console.log(`Demo member: Ada Obi, ${DEMO_PHONE}, demo PIN ${DEMO_PIN} (enable DEMO_LOGIN_ENABLED for "Try the demo").`);
} catch (err) {
  console.error(`Seeding failed: ${(err as Error).message}`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
