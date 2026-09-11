import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";
export default defineConfig({
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  // Scheduling tests ported from Cal.diy assume the server clock runs in UTC, as Vercel does.
  test: { include: ["tests/*.test.ts"], exclude: ["tests/*.integration.test.ts"], env: { TZ: "UTC" } },
});
