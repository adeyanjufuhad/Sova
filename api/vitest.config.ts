import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globalSetup: ["./test/setup/global.ts"],
    // Starting Postgres on a cold machine can take a while.
    hookTimeout: 120_000,
    testTimeout: 30_000,
  },
});
