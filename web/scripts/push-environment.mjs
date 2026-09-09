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
const values = { NEXT_PUBLIC_SITE_URL: "https://murmur-rho-pied.vercel.app" };
for (const name of names)
  if (process.env[name]) values[name] = process.env[name];
for (const [name, value] of Object.entries(values)) {
  const result = spawnSync(
    "vercel",
    [
      "env",
      "add",
      name,
      "production",
      "--yes",
      "--force",
      "--scope",
      "jason-zanes-projects",
    ],
    { input: value, encoding: "utf8" },
  );
  if (result.status !== 0)
    throw new Error(`Could not set ${name}: ${result.stderr}`);
  console.log(`${name} configured`);
}
