import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { createPool } from "./db.js";
import { createProofStorage, S3ProofStorage } from "./lib/storage.js";
import { loadMigrations, migrate, resolveMigrationsDir } from "./migrate/runner.js";

const config = loadConfig();
const pool = createPool(config);
const app = await buildApp(config, pool);

if (pool && config.RUN_MIGRATIONS_ON_START) {
  // Prefer running `npm run migrate:prod` as an admin before deploying; this is
  // for platforms without a pre-deploy step. Needs a role allowed to run DDL.
  const applied = await migrate(pool, loadMigrations(resolveMigrationsDir(process.env.MIGRATIONS_DIR)), (m) =>
    app.log.info(m),
  );
  app.log.info({ applied: applied.length }, "migrations checked");
}

// Graceful shutdown so in-flight requests finish during redeploys.
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, async () => {
    app.log.info({ signal }, "shutting down");
    await app.close();
    await pool?.end();
    process.exit(0);
  });
}

try {
  await app.listen({ host: config.HOST, port: config.PORT });
} catch (err) {
  app.log.fatal({ err }, "failed to start");
  process.exit(1);
}

// Let the app's own origins upload receipt photos straight to the bucket.
// Best-effort: if the bucket refuses, uploads from browsers fail but the API runs.
const storage = createProofStorage(config);
if (storage instanceof S3ProofStorage && config.CORS_ORIGINS.length) {
  storage
    .allowBrowserUploads(config.CORS_ORIGINS)
    .then(() => app.log.info({ origins: config.CORS_ORIGINS }, "bucket allows browser uploads"))
    .catch((err: Error) => app.log.warn({ reason: err.name }, "could not set bucket CORS; browser uploads may fail"));
}
