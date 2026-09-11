import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { createClient, type OAuthClient, type SupabaseClient } from "@supabase/supabase-js";
import { POST as mcp } from "../src/app/mcp/route";
import { POST as save, GET as library } from "../src/app/api/sessions/route";
import { newDocument } from "../src/lib/documents";
import { bearerClient } from "../src/lib/supabase/server";

// Run only through scripts/test-integration.mjs. It supplies the isolated local stack's
// credentials; this fixture refuses every hosted URL, including Murmur production.
const api = process.env.NEXT_PUBLIC_SUPABASE_URL!;
if (api !== "http://127.0.0.1:56321") throw new Error("Integration tests require isolated local Murmur.");
const auth = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };
const admin = createClient(api, process.env.SUPABASE_SECRET_KEY!, { auth });
const site = (process.env.NEXT_PUBLIC_SITE_URL || "https://murmur-rho-pied.vercel.app").replace(/\/$/, "");
const makeClient = () => createClient(api, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, { auth });
const users: string[] = [], clients: string[] = [];
const document = newDocument("Private integration fixture");
document.note = "The Cobalt worksheet is due Monday.";
let owner: SupabaseClient, ownerToken: string, otherToken: string;
let desktop: OAuthClient, external: OAuthClient, desktopToken: string, externalToken: string, externalRefresh: string;

function request(path: string, token: string, body?: unknown) {
  return new Request(`${site}/${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}
async function createUser() {
  const email = `murmur-${randomUUID()}@example.invalid`, password = randomBytes(24).toString("base64url");
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (created.error) throw created.error;
  users.push(created.data.user.id);
  const client = makeClient();
  const signed = await client.auth.signInWithPassword({ email, password });
  if (signed.error) throw signed.error;
  return { client, token: signed.data.session.access_token };
}
async function createOAuthClient(name: string) {
  const result = await admin.auth.admin.oauth.createClient({
    client_name: name, redirect_uris: ["murmur://oauth/callback"],
    grant_types: ["authorization_code", "refresh_token"], response_types: ["code"],
    scope: "openid email profile", token_endpoint_auth_method: "none",
  });
  if (result.error) throw result.error;
  clients.push(result.data.client_id);
  return result.data;
}
async function authorize(client: OAuthClient) {
  const verifier = randomBytes(32).toString("base64url"), state = randomUUID();
  const query = new URLSearchParams({
    client_id: client.client_id, response_type: "code", redirect_uri: "murmur://oauth/callback",
    scope: "openid email profile", state,
    code_challenge: createHash("sha256").update(verifier).digest("base64url"), code_challenge_method: "S256",
  });
  const response = await fetch(`${api}/auth/v1/oauth/authorize?${query}`, { redirect: "manual" });
  const location = response.headers.get("location");
  if (!location) throw new Error(`OAuth authorization did not redirect (${response.status}): ${await response.text()}`);
  const authorizationID = new URL(location).searchParams.get("authorization_id")!;
  const details = await owner.auth.oauth.getAuthorizationDetails(authorizationID);
  if (details.error) throw details.error;
  const approval = await owner.auth.oauth.approveAuthorization(authorizationID, { skipBrowserRedirect: true });
  if (approval.error) throw approval.error;
  const callback = new URL(approval.data.redirect_url);
  expect(callback.searchParams.get("state")).toBe(state);
  const tokenResponse = await fetch(`${api}/auth/v1/oauth/token`, {
    method: "POST", body: new URLSearchParams({
      grant_type: "authorization_code", client_id: client.client_id, code: callback.searchParams.get("code")!,
      redirect_uri: "murmur://oauth/callback", code_verifier: verifier,
    }),
  });
  if (!tokenResponse.ok) throw new Error(`OAuth exchange failed (${tokenResponse.status}): ${await tokenResponse.text()}`);
  return tokenResponse.json();
}
beforeAll(async () => {
  const first = await createUser(), second = await createUser();
  owner = first.client; ownerToken = first.token; otherToken = second.token;
  desktop = await createOAuthClient("Murmur integration Mac");
  external = await createOAuthClient("Murmur integration AI");
  const registered = await admin.from("first_party_clients").insert({ client_id: desktop.client_id, label: "Integration Mac" });
  if (registered.error) throw registered.error;
  const native = await authorize(desktop), ai = await authorize(external);
  desktopToken = native.access_token; externalToken = ai.access_token; externalRefresh = ai.refresh_token;
});
afterAll(async () => {
  for (const id of clients) {
    await admin.from("first_party_clients").delete().eq("client_id", id);
    await admin.auth.admin.oauth.deleteClient(id);
  }
  for (const id of users) await admin.auth.admin.deleteUser(id);
});

describe("real local Auth, Postgres policies and MCP", () => {
  it("issues signed tokens with separate native and MCP audiences", async () => {
    const native = await bearerClient(desktopToken).auth.getClaims(desktopToken);
    const ai = await bearerClient(externalToken).auth.getClaims(externalToken);
    expect(native.error).toBeNull(); expect(ai.error).toBeNull();
    expect(native.data?.claims.aud).toBe("authenticated");
    expect(ai.data?.claims.aud).toBe(`${site}/mcp`);
    expect(ai.data?.claims.client_id).toBe(external.client_id);
  });
  it("lets the Mac save, retries idempotently and rejects stale overwrites", async () => {
    const first = await save(request("api/sessions", desktopToken, { document, expectedVersion: 0 }));
    expect(first.status, await first.clone().text()).toBe(200);
    expect((await first.json()).version).toBe(1);
    expect((await (await save(request("api/sessions", desktopToken, { document, expectedVersion: 0 }))).json()).version).toBe(1);
    const revised = structuredClone(document); revised.note = "The worksheet deadline moved to Tuesday.";
    expect((await save(request("api/sessions", ownerToken, { document: revised, expectedVersion: 1 }))).status).toBe(200);
    expect((await save(request("api/sessions", desktopToken, { document, expectedVersion: 1 }))).status).toBe(409);
    const history = await bearerClient(desktopToken).from("session_revisions").select("document");
    expect(history.data?.[0].document.note).toBe(document.note);
  });
  it("isolates accounts and refuses AI writes even through the direct database API", async () => {
    const own = await library(request("api/sessions", ownerToken));
    expect((await own.json()).sessions).toHaveLength(1);
    const other = await library(request("api/sessions", otherToken));
    expect((await other.json()).sessions).toHaveLength(0);
    const ai = bearerClient(externalToken);
    const write = await ai.rpc("put_session", { p_document: document, p_expected_version: 2 });
    expect(write.error?.code).toBe("42501");
    const credentials = await ai.from("calendar_credentials").select("*");
    expect(credentials.error?.code).toBe("42501");
  });
  it("serves real notes to MCP while rejecting ordinary sessions and forged signatures", async () => {
    const call = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "get_session", arguments: { id: document.session.id } } };
    const response = await mcp(request("mcp", externalToken, call));
    expect(response.status).toBe(200);
    const result = await response.json();
    expect(result.result.isError).not.toBe(true);
    expect(JSON.parse(result.result.content[0].text).note).toContain("Tuesday");
    expect((await mcp(request("mcp", ownerToken, call))).status).toBe(401);
    expect((await mcp(request("mcp", desktopToken, call))).status).toBe(401);
    const parts = externalToken.split("."); parts[2] = (parts[2][0] === "A" ? "B" : "A") + parts[2].slice(1);
    expect((await mcp(request("mcp", parts.join("."), call))).status).toBe(401);
  });
  it("refreshes the OAuth grant without losing the MCP audience", async () => {
    const response = await fetch(`${api}/auth/v1/oauth/token`, { method: "POST", body: new URLSearchParams({
      grant_type: "refresh_token", client_id: external.client_id, refresh_token: externalRefresh,
    }) });
    expect(response.status).toBe(200);
    const token = await response.json();
    const verified = await bearerClient(token.access_token).auth.getClaims(token.access_token);
    expect(verified.error).toBeNull();
    expect(verified.data?.claims.aud).toBe(`${site}/mcp`);
  });
});
