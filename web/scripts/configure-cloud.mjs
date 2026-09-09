// Run from web/ after placing the Murmur project's credentials in .env.local.
// It never reads the globally configured Supabase CLI account and never prints secrets.
import { readFile, writeFile, chmod } from "node:fs/promises";
import { createClient } from "@supabase/supabase-js";
import { findDesktopClient } from "./oauth-clients.mjs";
process.loadEnvFile(".env.local");
const project = "olxjfdsslbpdvywsnzrc";
const origin = "https://murmur-rho-pied.vercel.app";
const managed = process.env.MURMUR_SUPABASE_MANAGEMENT_TOKEN;
async function management(path, method = "GET", body) {
  if (!managed)
    throw new Error(
      "Use the Supabase dashboard for Auth settings, or provide a Murmur-authorized management token.",
    );
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${project}/${path}`,
    {
      method,
      headers: {
        Authorization: `Bearer ${managed}`,
        "Content-Type": "application/json",
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
      signal: AbortSignal.timeout(30000),
    },
  );
  if (!response.ok)
    throw new Error(
      `Supabase management request failed (${response.status}) at ${path}. No credential has been printed.`,
    );
  return response.json();
}
async function saveEnv(name, value) {
  const file = ".env.local";
  let text = await readFile(file, "utf8");
  const line = `${name}=${value}`;
  const pattern = new RegExp(`^${name}=.*$`, "m");
  text = pattern.test(text)
    ? text.replace(pattern, line)
    : `${text.trimEnd()}\n${line}\n`;
  await writeFile(file, text);
  await chmod(file, 0o600);
  process.env[name] = value;
}
if (process.env.NEXT_PUBLIC_SUPABASE_URL !== `https://${project}.supabase.co`)
  throw new Error("This script only configures the dedicated Murmur project.");
if (managed) {
  const existing = await management("config/auth");
  const redirects = new Set(
    (existing.uri_allow_list || "").split(",").filter(Boolean),
  );
  redirects.add(`${origin}/auth/callback`);
  redirects.add("murmur://oauth/callback");
  const settings = {
    site_url: origin,
    uri_allow_list: [...redirects].join(","),
    oauth_server_enabled: true,
    oauth_server_authorization_path: "/oauth/consent",
    oauth_server_allow_dynamic_registration: true,
    hook_custom_access_token_enabled: true,
    hook_custom_access_token_uri:
      "pg-functions://postgres/public/murmur_access_token_hook",
  };
  if (process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET)
    Object.assign(settings, {
      external_google_enabled: true,
      external_google_client_id: process.env.GOOGLE_CLIENT_ID,
      external_google_secret: process.env.GOOGLE_CLIENT_SECRET,
    });
  await management("config/auth", "PATCH", settings);
  if (!process.env.SUPABASE_SECRET_KEY) {
    const keys = await management("api-keys");
    const key = keys.find((k) => k.type === "secret" && !k.disabled);
    if (key?.api_key) await saveEnv("SUPABASE_SECRET_KEY", key.api_key);
  }
  console.log(
    "Murmur Auth URL, OAuth server and resource audience hook configured.",
  );
}
if (!process.env.SUPABASE_SECRET_KEY)
  throw new Error(
    "Add this project’s server-only secret key to .env.local to register the Mac app.",
  );
const client = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SECRET_KEY,
  { auth: { persistSession: false, autoRefreshToken: false } },
);
let desktop = await findDesktopClient(client.auth.admin.oauth);
if (!desktop) {
  const result = await client.auth.admin.oauth.createClient({
    client_name: "Voice Notes for Mac",
    client_uri: origin,
    redirect_uris: ["murmur://oauth/callback"],
    grant_types: ["authorization_code", "refresh_token"],
    response_types: ["code"],
    scope: "openid email profile",
    token_endpoint_auth_method: "none",
  });
  if (result.error) throw result.error;
  desktop = result.data;
}
const { error: registration } = await client
  .from("first_party_clients")
  .upsert({ client_id: desktop.client_id, label: "Voice Notes for Mac" });
if (registration) throw registration;
await saveEnv("MURMUR_DESKTOP_CLIENT_ID", desktop.client_id);
if (process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET)
  await saveEnv("NEXT_PUBLIC_GOOGLE_ENABLED", "true");
console.log(
  "The public Mac OAuth client is registered. Upload the required app environment variables to Vercel and deploy.",
);
