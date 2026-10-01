// Explicit production-only QA, using existing configuration in process memory.
// No environment download, key/client creation, provider access or persistent config changes.
import { readFileSync } from "node:fs";
import { parseEnv } from "node:util";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const project = "olxjfdsslbpdvywsnzrc";
const args = process.argv.slice(2);
if (args.length !== 3 || args[0] !== "--existing-config" || args[2] !== `--confirm-production=${project}`) {
  throw Error("Requires --existing-config <existing file> and exact --confirm-production=olxjfdsslbpdvywsnzrc. Refuses all other projects.");
}
const parsed = parseEnv(readFileSync(args[1], "utf8"));
const required = ["NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "SUPABASE_SECRET_KEY"];
const config = Object.fromEntries(required.map(key => [key, parsed[key]]));
if (config.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, "") !== `https://${project}.supabase.co` || required.some(key => !config[key])) {
  throw Error("Existing configuration does not match the verified production project or lacks a required entry. No fixture action performed.");
}
// Discard all other source configuration; only these three values enter the child.
for (const key of Object.keys(parsed)) delete parsed[key];
const inherited = ["PATH", "HOME", "TMPDIR", "LANG", "SSL_CERT_FILE", "NODE_EXTRA_CA_CERTS"];
const env = Object.fromEntries(inherited.filter(key => process.env[key]).map(key => [key, process.env[key]]));
Object.assign(env, config, { CONCOURSE_PRODUCTION_QA: project, FOLLOW_UP_DRAFTS_ENABLED: "true", NEXT_PUBLIC_SITE_URL: "https://murmur-rho-pied.vercel.app", TZ: "UTC" });
const cwd = fileURLToPath(new URL("../", import.meta.url));
const child = spawn(process.execPath, [fileURLToPath(new URL("../node_modules/vitest/vitest.mjs", import.meta.url)), "run", "--config", "vitest.production-qa.config.ts"], { cwd, env, stdio: "inherit" });
for (const key of required) { delete config[key]; delete env[key]; }
child.once("error", () => { console.error("Production QA process could not start. No credentials are printed."); process.exitCode = 1; });
child.once("exit", code => { process.exitCode = code ?? 1; });
