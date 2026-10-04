import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { commitmentOf, drawOrder } from "../src/lib/draw.js";
import { DEMO_PHONE, seedDemo } from "../src/seed/demo.js";
import { freshDatabase } from "./setup/db.js";

let db: Awaited<ReturnType<typeof freshDatabase>>;

beforeAll(async () => {
  db = await freshDatabase();
});
afterAll(async () => db.drop());

describe("demo seed", () => {
  it("creates circles in every state the demo needs", async () => {
    const result = await seedDemo(db.pool);
    expect(result.circles).toBe(5);

    const { rows } = await db.pool.query<{ name: string; status: string; members: number; active: number }>(`
      select g.name, g.status,
             (select count(*)::int from group_members m where m.group_id = g.id) as members,
             (select count(*)::int from rounds r where r.group_id = g.id and r.status = 'active') as active
        from groups g order by g.name`);
    const byName = Object.fromEntries(rows.map((r) => [r.name, r]));
    expect(byName["Church Adashe"]).toMatchObject({ status: "completed", active: 0 });
    expect(byName["Office Esusu"]).toMatchObject({ members: 6, active: 1 });
    expect(byName["Ikeja Tech Hub Esusu"]).toMatchObject({ status: "forming", members: 4, active: 0 });

    const disputes = await db.pool.query("select status from disputes");
    expect(disputes.rows).toEqual([{ status: "open" }]);
  });

  it("flags the member who collected then stopped paying", async () => {
    const { rows } = await db.pool.query(
      `select u.full_name from unfinished_obligations o join users u on u.id = o.user_id`,
    );
    expect(rows.map((r) => r.full_name)).toContain("Musa Kabir");
  });

  it("leaves turns undrawn in the new circle", async () => {
    const { rows } = await db.pool.query(
      `select count(*)::int as n from group_members m join groups g on g.id = m.group_id
        where g.invite_code = 'T7KP9Q' and m.payout_position is not null`,
    );
    expect(rows[0].n).toBe(0);
  });

  it("gives every started circle a draw that verifies, and keeps the forming one secret", async () => {
    const { rows } = await db.pool.query<{
      status: string;
      commitment: string;
      seed: string;
      revealed_at: Date | null;
      admin_id: string;
      admin_collects_last: boolean;
      members: string[];
    }>(`
      select g.status, d.commitment, d.seed, d.revealed_at, g.admin_id, g.admin_collects_last,
             array(select user_id::text from group_members m where m.group_id = g.id order by m.payout_position) as members
        from groups g join circle_draws d on d.group_id = g.id`);
    expect(rows).toHaveLength(5);
    for (const r of rows) {
      expect(commitmentOf(r.seed)).toBe(r.commitment);
      if (r.status === "forming") {
        expect(r.revealed_at).toBeNull();
        continue;
      }
      expect(r.revealed_at).not.toBeNull();
      expect(drawOrder(r.seed, r.members, r.admin_id, r.admin_collects_last)).toEqual(r.members);
    }
  });

  it("computes Sova Scores with the database function", async () => {
    const { rows } = await db.pool.query(
      `select s.score_value from scores s join users u on u.id = s.user_id where u.phone = $1`,
      [DEMO_PHONE],
    );
    expect(rows.length).toBe(1);
    expect(rows[0].score_value).toBeGreaterThan(0);
  });

  it("is safe to run again and leaves real users alone", async () => {
    await db.pool.query("insert into users (phone, full_name) values ('+2348031234567', 'Real Person')");
    await seedDemo(db.pool);
    const groups = await db.pool.query("select count(*)::int as n from groups");
    expect(groups.rows[0].n).toBe(5);
    const real = await db.pool.query("select count(*)::int as n from users where phone = '+2348031234567'");
    expect(real.rows[0].n).toBe(1);
  });

  it("makes the demo login work", async () => {
    const app = await buildApp(
      loadConfig({
        NODE_ENV: "test",
        LOG_LEVEL: "silent",
        JWT_SECRET: "test-secret-that-is-at-least-32-characters-long",
        DEMO_LOGIN_ENABLED: "true",
      }),
      db.pool,
    );
    const res = await app.inject({ method: "POST", url: "/auth/demo" });
    expect(res.statusCode).toBe(200);
    expect(res.json().user).toMatchObject({ fullName: "Ada Obi", hasPin: true, isDemo: true });
  });
});
