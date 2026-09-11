// Only app settings go to Vercel. Management tokens never leave this machine.
import { spawnSync } from "node:child_process";
process.loadEnvFile(".env.local");
const names = [
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  "NEXT_PUBLIC_GOOGLE_ENABLED",
  "MURMUR_DESKTOP_CLIENT_ID",
  "SUPABASE_SECRET_KEY",
  "GOOGLE_TOKEN_ENCRYPTION_KEY",
  "GOOGLE_CLIENT_ID",
  "GOOGLE_CLIENT_SECRET",
];
if (!process.env.NEXT_PUBLIC_SITE_URL)
  throw new Error("Set NEXT_PUBLIC_SITE_URL in .env.local to the deployment's https origin.");
const values = { NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL };
for (const name of names)
  if (process.env[name]) values[name] = process.env[name];
// `--scope` only when a team is named; a personal Vercel account has none.
const scope = process.env.VERCEL_SCOPE ? ["--scope", process.env.VERCEL_SCOPE] : [];
for (const [name, value] of Object.entries(values)) {
  const result = spawnSync(
    "vercel",
    ["env", "add", name, "production", "--yes", "--force", ...scope],
    { input: value, encoding: "utf8" },
  );
  if (result.status !== 0)
    throw new Error(`Could not set ${name}: ${result.stderr}`);
  console.log(`${name} configured`);
}
