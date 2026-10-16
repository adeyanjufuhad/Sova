import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { createPool } from "./db.js";
import { loadMigrations, migrate, resolveMigrationsDir } from "./migrate/runner.js";
import { topUpDemoSpares } from "./seed/demo.js";

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

// A sleeping deployment wakes on its first request: have a demo copy ready by
// the time that visitor taps "Try the demo".
if (pool && config.DEMO_LOGIN_ENABLED && config.DEMO_SPARES > 0) {
  topUpDemoSpares(pool, config.DEMO_SPARES).then(
    (built) => app.log.info({ built }, "demo: spare copies ready"),
    (err) => app.log.error({ err }, "demo: spare copy not built"),
  );
}
