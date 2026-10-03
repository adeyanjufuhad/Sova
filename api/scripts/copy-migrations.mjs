// Copies ../db/migrations into dist/migrations at build time, so the compiled
// API can migrate even when it is deployed without the rest of the repository.
import { cpSync, existsSync, rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const api = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = path.resolve(api, "../db/migrations");
const target = path.resolve(api, "dist/migrations");

if (!existsSync(source)) {
  console.warn(`copy-migrations: ${source} not found; relying on MIGRATIONS_DIR at runtime.`);
  process.exit(0);
}
rmSync(target, { recursive: true, force: true });
cpSync(source, target, { recursive: true });
console.log(`copy-migrations: copied db/migrations to dist/migrations`);
