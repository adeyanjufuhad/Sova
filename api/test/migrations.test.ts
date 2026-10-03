import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type pg from "pg";

import { loadMigrations, migrate, resolveMigrationsDir } from "../src/migrate/runner.js";
import { freshDatabase } from "./setup/db.js";

let db: Awaited<ReturnType<typeof freshDatabase>>;
let pool: pg.Pool;

beforeAll(async () => {
  db = await freshDatabase();
  pool = db.pool;
});
afterAll(async () => db.drop());

describe("migrations", () => {
  it("apply cleanly to a fresh database and record each version", async () => {
    const { rows } = await pool.query("select version from schema_migrations order by version");
    const files = loadMigrations(resolveMigrationsDir()).map((m) => m.version);
    expect(rows.map((r) => r.version)).toEqual(files);
  });

  it("are idempotent: a second run applies nothing", async () => {
    expect(await migrate(pool, loadMigrations(resolveMigrationsDir()))).toEqual([]);
  });

  it("refuse a migration that changed after being applied", async () => {
    const migrations = loadMigrations(resolveMigrationsDir());
    const tampered = migrations.map((m, i) => (i === 0 ? { ...m, checksum: "different" } : m));
    await expect(migrate(pool, tampered)).rejects.toThrow(/changed after it was applied/);
  });

  it("let payout positions stay empty until the draw", async () => {
    const { rows } = await pool.query(
      "select is_nullable from information_schema.columns where table_name = 'group_members' and column_name = 'payout_position'",
    );
    expect(rows[0].is_nullable).toBe("YES");
  });

  it("only accept invite codes without look-alike characters", async () => {
    const user = await pool.query("insert into users (phone, full_name) values ('+2348030000001', 'Ada Obi') returning id");
    const insert = (code: string) =>
      pool.query(
        `insert into groups (name, admin_id, member_count, contribution_amount, cycle_type, start_date, invite_code)
         values ('Test', $1, 3, 1000, 'weekly', current_date, $2)`,
        [user.rows[0].id, code],
      );
    await expect(insert("K7QX2M")).resolves.toBeDefined();
    await expect(insert("K0QX1M")).rejects.toThrow(/groups_invite_code_format/);
  });

  it("measure payout shortfall against contributions from the other members", async () => {
    const mk = async (phone: string) =>
      (await pool.query("insert into users (phone) values ($1) returning id", [phone])).rows[0].id as string;
    const [a, b, c] = [await mk("+2348031000001"), await mk("+2348031000002"), await mk("+2348031000003")];
    const g = (
      await pool.query(
        `insert into groups (name, admin_id, member_count, contribution_amount, cycle_type, start_date, invite_code)
         values ('Payout', $1, 3, 10000, 'weekly', current_date, 'PAYABC') returning id`,
        [a],
      )
    ).rows[0].id;
    for (const [i, u] of [a, b, c].entries()) {
      await pool.query("insert into group_members (group_id, user_id, payout_position) values ($1, $2, $3)", [g, u, i + 1]);
    }
    await pool.query("select force_advance_round($1)", [g]);
    const round = (await pool.query("select id from rounds where group_id = $1 and status = 'active'", [g])).rows[0].id;

    // Collector a should receive 2 x 10,000. Only 15,000 arrived.
    const short = await pool.query("select confirm_payout($1, $2, 15000) as s", [round, a]);
    expect(short.rows[0].s).toBe(5000);
    await expect(pool.query("select confirm_payout($1, $2, 20000)", [round, a])).rejects.toThrow(/already confirmed/);
  });
});
