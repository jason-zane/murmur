// A disposable-account integration run against this repo's local Supabase stack.
// Never reads .env.local, global Supabase credentials or a hosted project.
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { access, readFile, writeFile } from "node:fs/promises";
import { generateKeyPairSync, randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
const run = promisify(execFile);
const root = fileURLToPath(new URL("../../", import.meta.url));
const web = fileURLToPath(new URL("../", import.meta.url));
const keysPath = new URL("../../supabase/signing_keys.json", import.meta.url);
try { await access(keysPath); } catch {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const key = { ...privateKey.export({ format: "jwk" }), kid: randomUUID(), alg: "ES256", use: "sig", key_ops: ["sign", "verify"] };
  await writeFile(keysPath, JSON.stringify([key]), { mode: 0o600 });
}
console.log("Starting the isolated Murmur stack on port 56321…");
try {
  await run("supabase", ["start", "-x", "studio,meta,realtime,storage,imgproxy,edge-runtime,analytics,vector"], { cwd: root, maxBuffer: 8 * 1024 * 1024 });
} catch {
  throw new Error("Local Murmur startup failed. Inspect `supabase start` in this repository; no credentials were printed.");
}
const { stdout } = await run("supabase", ["status", "-o", "json"], { cwd: root });
const local = JSON.parse(stdout);
if (local.API_URL !== "http://127.0.0.1:56321") throw new Error("Refusing an unexpected Supabase stack.");
const sql = await readFile(new URL("../../supabase/tests/cloud-access.sql", import.meta.url), "utf8");
await new Promise((resolve, reject) => {
  const child = spawn("docker", ["exec", "-i", "supabase_db_murmur", "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-q"], { cwd: root, stdio: ["pipe", "pipe", "pipe"] });
  let output = "", error = "";
  child.stdout.on("data", chunk => output += chunk);
  child.stderr.on("data", chunk => error += chunk);
  child.on("error", reject);
  child.on("exit", code => code === 0 ? resolve(output) : reject(new Error(error)));
  child.stdin.end(sql);
});
console.log("Rollback-only SQL checks passed.");
const exitCode = await new Promise((resolve, reject) => {
  const child = spawn(process.execPath, ["node_modules/vitest/vitest.mjs", "run", "--config", "vitest.integration.config.ts"], {
    cwd: web, stdio: "inherit", env: {
      ...process.env,
      NEXT_PUBLIC_SUPABASE_URL: local.API_URL,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: local.PUBLISHABLE_KEY || local.ANON_KEY,
      SUPABASE_SECRET_KEY: local.SECRET_KEY || local.SERVICE_ROLE_KEY,
      NEXT_PUBLIC_SITE_URL: "https://murmur-rho-pied.vercel.app",
      NEXT_PUBLIC_GOOGLE_ENABLED: "false",
    },
  });
  child.on("error", reject); child.on("exit", resolve);
});
console.log("Fixtures removed. The isolated stack remains available for development; stop it with `supabase stop` from this repository.");
process.exitCode = exitCode ?? 1;
