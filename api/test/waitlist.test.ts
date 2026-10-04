import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { freshDatabase } from "./setup/db.js";

let db: Awaited<ReturnType<typeof freshDatabase>>;
let ip = 0;

beforeAll(async () => {
  db = await freshDatabase();
});
afterAll(async () => db.drop());

async function join(payload: object) {
  const app = await buildApp(
    loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent", JWT_SECRET: "test-secret-that-is-at-least-32-characters-long" }),
    db.pool,
  );
  return app.inject({ method: "POST", url: "/waitlist", payload, remoteAddress: `10.2.0.${++ip}` });
}

describe("waitlist", () => {
  it("saves a sign-up with the phone normalised, once per number", async () => {
    const first = await join({ name: "Adaeze Okafor", phone: "0803 123 4567", role: "member", city: "Balogun", groupSize: "12" });
    expect(first.statusCode).toBe(201);
    expect((await join({ name: "Adaeze Okafor", phone: "+2348031234567", role: "admin" })).statusCode).toBe(201);
    const { rows } = await db.pool.query("select name, phone, role, city, group_size from waitlist");
    expect(rows).toEqual([{ name: "Adaeze Okafor", phone: "+2348031234567", role: "member", city: "Balogun", group_size: 12 }]);
  });

  it("explains bad input", async () => {
    const res = await join({ name: "Ada", phone: "12345", role: "member" });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message).toMatch(/Nigerian phone number/);
  });

  it("quietly ignores bots that fill the honeypot", async () => {
    const res = await join({ name: "Bot", phone: "08099999999", role: "member", website: "http://spam" });
    expect(res.statusCode).toBe(201);
    const { rows } = await db.pool.query("select count(*)::int as n from waitlist where phone = '+2348099999999'");
    expect(rows[0].n).toBe(0);
  });
});
