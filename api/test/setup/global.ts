/**
 * Vitest global setup: starts a throwaway PostgreSQL 17 (embedded-postgres,
 * no Docker), applies every migration to a template database, and shares its
 * address with the tests. Each test file clones the template, so tests start
 * from a clean, fully migrated database in milliseconds.
 */
import { mkdtempSync, rmSync } from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

import EmbeddedPostgres from "embedded-postgres";
import pg from "pg";
import type { TestProject } from "vitest/node";

import { loadMigrations, migrate, resolveMigrationsDir } from "../../src/migrate/runner.js";

declare module "vitest" {
  export interface ProvidedContext {
    pgPort: number;
    pgPassword: string;
    templateDb: string;
  }
}

async function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, () => {
      const { port } = srv.address() as net.AddressInfo;
      srv.close(() => resolve(port));
    });
    srv.on("error", reject);
  });
}

export default async function setup(project: TestProject) {
  const dir = mkdtempSync(path.join(os.tmpdir(), "sova-pg-"));
  const port = await freePort();
  const password = "test-only-password";
  const server = new EmbeddedPostgres({
    databaseDir: dir,
    user: "postgres",
    password,
    port,
    persistent: false,
    // UTF-8 like production; Windows would otherwise default to WIN1252 and reject "₦".
    initdbFlags: ["--encoding=UTF8", "--locale=C"],
    onLog: () => {},
  });
  await server.initialise();
  await server.start();
  await server.createDatabase("sova_template");

  const pool = new pg.Pool({ host: "localhost", port, user: "postgres", password, database: "sova_template" });
  await migrate(pool, loadMigrations(resolveMigrationsDir()));
  await pool.end();

  project.provide("pgPort", port);
  project.provide("pgPassword", password);
  project.provide("templateDb", "sova_template");

  return async () => {
    await server.stop();
    rmSync(dir, { recursive: true, force: true });
  };
}
