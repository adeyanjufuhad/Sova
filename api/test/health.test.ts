import { describe, expect, it } from "vitest";
import type pg from "pg";

import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";

const config = loadConfig({ NODE_ENV: "test", LOG_LEVEL: "silent" });

describe("GET /health", () => {
  it("is healthy when no database is configured yet", async () => {
    const app = await buildApp(config, null);
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: "ok", database: "not_configured" });
    await app.close();
  });

  it("reports the database as ok when it answers", async () => {
    const pool = { query: async () => ({ rows: [{ "?column?": 1 }] }) } as unknown as pg.Pool;
    const app = await buildApp(config, pool);
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: "ok", database: "ok" });
    await app.close();
  });

  it("returns 503 when the database is configured but unreachable", async () => {
    const pool = {
      query: async () => {
        throw new Error("connection refused");
      },
    } as unknown as pg.Pool;
    const app = await buildApp(config, pool);
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(503);
    expect(res.json()).toMatchObject({ status: "degraded", database: "unavailable" });
    await app.close();
  });
});

describe("config", () => {
  it("rejects a malformed database URL with a clear message", () => {
    expect(() => loadConfig({ DATABASE_URL: "not a url" })).toThrow(/DATABASE_URL/);
  });

  it("parses CORS origins from a comma-separated list", () => {
    const c = loadConfig({ CORS_ORIGINS: "https://a.example, https://b.example ," });
    expect(c.CORS_ORIGINS).toEqual(["https://a.example", "https://b.example"]);
  });

  it("defaults to port 8080", () => {
    expect(loadConfig({}).PORT).toBe(8080);
  });
});
