import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";
export default defineConfig({
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  test: { include: ["tests/production-follow-up.integration.test.ts"], fileParallelism: false, testTimeout: 90000, hookTimeout: 60000, env: { TZ: "UTC" } },
});
