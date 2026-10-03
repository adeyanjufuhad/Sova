import { randomUUID } from "node:crypto";

import pg from "pg";
import { inject } from "vitest";

/**
 * A fresh, fully migrated database cloned from the template for one test file.
 * Call `drop()` in afterAll.
 */
export async function freshDatabase(): Promise<{ pool: pg.Pool; url: string; drop: () => Promise<void> }> {
  const port = inject("pgPort");
  const password = inject("pgPassword");
  const name = `t_${randomUUID().replace(/-/g, "")}`;
  const admin = new pg.Client({ host: "localhost", port, user: "postgres", password, database: "postgres" });
  await admin.connect();
  await admin.query(`create database ${name} template ${inject("templateDb")}`);
  await admin.end();

  const url = `postgres://postgres:${password}@localhost:${port}/${name}`;
  const pool = new pg.Pool({ connectionString: url, max: 5 });
  return {
    pool,
    url,
    drop: async () => {
      await pool.end();
      const c = new pg.Client({ host: "localhost", port, user: "postgres", password, database: "postgres" });
      await c.connect();
      await c.query(`drop database if exists ${name} with (force)`);
      await c.end();
    },
  };
}
