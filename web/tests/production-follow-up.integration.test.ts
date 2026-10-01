import { afterAll, beforeAll, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { newDocument } from "../src/lib/documents";
import { bearerClient } from "../src/lib/supabase/server";
import { POST as saveNote } from "../src/app/api/sessions/route";
import { GET as read, PUT as save } from "../src/app/api/sessions/[id]/follow-up/route";

// This file is excluded from normal tests. Never run the local integration launcher.
const project = "olxjfdsslbpdvywsnzrc";
const api = `https://${project}.supabase.co`;
if (process.env.CONCOURSE_PRODUCTION_QA !== project || process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, "") !== api) {
  throw Error("Refusing production fixture without exact project opt-in.");
}
const auth = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };
const admin = createClient(api, process.env.SUPABASE_SECRET_KEY!, { auth });
const makeClient = () => createClient(api, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, { auth });
const run = randomUUID();
const users: { id: string; email: string; tokens: string[] }[] = [];
const site = "https://murmur-rho-pied.vercel.app";
let owner: SupabaseClient, token: string, secondSession: string, otherToken: string;
const note = newDocument(`Synthetic release QA ${run}`);
note.session.id = `release-qa-${run}`;
note.note = "Synthetic pilot: confirm the checklist. The date is unresolved.";
const context = { params: Promise.resolve({ id: note.session.id }) };
function request(access: string, method: string, body?: unknown) {
  return new Request(`${site}/api/sessions/${note.session.id}/follow-up`, { method,
    headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
}
const put = (document: unknown, version: number, access = token) => save(request(access, "PUT", { document, expectedVersion: version }), context);
const get = (access = token) => read(request(access, "GET"), context);
const check = (name: string) => console.log(`PASS: ${name}`);
function safeError(operation: string, error: { code?: string; status?: number } | null) {
  if (error) throw Error(`${operation} failed (${error.code || error.status || "unknown"}); no credentials are logged.`);
}
async function createFixtureUser() {
  if (users.length >= 2) throw Error("Fixture account limit reached.");
  const email = `concourse-release-qa-${randomUUID()}@example.invalid`, password = randomBytes(32).toString("base64url");
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (created.error || !created.data.user) {
    // No blind create retry: an acknowledgement may have been lost.
    console.error(`Fixture create not confirmed; resolve only exact generated email ${email}.`);
    safeError("Fixture account creation", created.error);
    throw Error("Fixture account creation was not confirmed.");
  }
  const record = { id: created.data.user.id, email, tokens: [] as string[] };
  users.push(record);
  console.log(`Fixture acknowledged: ${record.id} ${email}`);
  const client = makeClient(), login = await client.auth.signInWithPassword({ email, password });
  safeError("Fixture sign-in", login.error);
  if (!login.data.session || login.data.user?.id !== record.id) throw Error("Fixture identity mismatch.");
  record.tokens.push(login.data.session.access_token);
  return { client, token: login.data.session.access_token, password, record };
}
beforeAll(async () => {
  // Missing schema fails before account creation. No source/private data is read.
  const available = await admin.from("follow_up_drafts").select("session_id").limit(0);
  safeError("Reviewed follow-up schema preflight", available.error);
  const first = await createFixtureUser(), second = await createFixtureUser();
  owner = first.client; token = first.token; otherToken = second.token;
  const another = makeClient(), login = await another.auth.signInWithPassword({ email: first.record.email, password: first.password });
  safeError("Second owner session", login.error);
  if (!login.data.session || login.data.user?.id !== first.record.id) throw Error("Second session identity mismatch.");
  secondSession = login.data.session.access_token; first.record.tokens.push(secondSession);
});
afterAll(async () => {
  const failures: string[] = [], ids = users.map(row => row.id);
  // New users have no connected services. Assert this before bounded cleanup.
  if (ids.length) for (const table of ["mail_outbox", "booking_messages", "calendar_connections", "calendar_sources", "calendar_jobs", "calendar_push_channels"]) {
    const rows = await admin.from(table).select("user_id", { count: "exact", head: true }).in("user_id", ids);
    if (rows.error || rows.count !== 0) failures.push(`${table} side-effect check failed`);
  }
  for (const row of users) {
    const verified = await admin.auth.admin.getUserById(row.id);
    if (verified.error || verified.data.user?.email !== row.email || !row.email.startsWith("concourse-release-qa-") || !row.email.endsWith("@example.invalid")) {
      failures.push(`Cleanup identity guard refused ${row.id}`); continue;
    }
    // Revoke fixture sessions before deletion; access-token validity also depends on
    // Auth getUser/FK/owner checks, never assume hard deletion alone revokes JWTs.
    for (const access of row.tokens.slice(0, 1)) {
      const result = await admin.auth.admin.signOut(access, "global");
      if (result.error) failures.push(`Fixture session revocation failed for ${row.id}`);
    }
    const deleted = await admin.auth.admin.deleteUser(row.id);
    if (deleted.error) { failures.push(`Fixture deletion failed for ${row.id}`); continue; }
    const remaining = await admin.auth.admin.getUserById(row.id);
    if (remaining.data.user) failures.push(`Fixture account remains ${row.id}`);
  }
  if (ids.length) for (const table of ["sessions", "session_revisions", "follow_up_drafts"]) {
    const rows = await admin.from(table).select("user_id", { count: "exact", head: true }).in("user_id", ids);
    if (rows.error || rows.count !== 0) failures.push(`${table} cleanup check failed`);
  }
  if (failures.length) throw Error(failures.join("; "));
  if (ids.length) check(`exact fixture cleanup: ${ids.length} accounts; no notes, drafts or provider/outbox side effects`);
});

it("verifies real production Auth/ownership and bounded simultaneous follow-up writes", async () => {
  const verified = await owner.auth.getUser(token);
  expect(verified.error).toBeNull(); expect(verified.data.user?.id).toBe(users[0].id);
  expect((await owner.rpc("is_murmur_editor")).data).toBe(true);
  const initial = await saveNote(new Request(`${site}/api/sessions`, { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify({ document: note, expectedVersion: 0 }) }));
  expect(initial.status).toBe(200); expect((await initial.json()).version).toBe(1);
  check("issuer-verified owner/editor and unchanged note save contract");
  const proposal = { sourceVersion: 1, recipe: "meeting-follow-up/v1", fields: { recipient: "sam@", subject: "Synthetic follow-up", body: "Incomplete work remains editable." }, evidence: [{ kind: "note", id: "note", text: "confirm the checklist" }], unknowns: ["Recipient and date missing"], reviewed: false };
  const same = await Promise.all([token, secondSession].map(access => put(proposal, 0, access)));
  for (const response of same) { expect(response.status).toBe(200); expect((await response.json()).draft.version).toBe(1); }
  expect((await owner.from("follow_up_drafts").select("session_id").eq("session_id", note.session.id)).data).toHaveLength(1);
  check("two real owner sessions deduplicate simultaneous first saves");
  const edits = ["Concurrent wording A", "Concurrent wording B"].map(body => ({ ...proposal, fields: { ...proposal.fields, body } }));
  const changed = await Promise.all(edits.map(document => put(document, 1)));
  expect(changed.map(response => response.status).sort()).toEqual([200, 409]);
  const winner = edits[changed.findIndex(response => response.status === 200)];
  // Intentionally discard the successful response and reconcile the lost acknowledgement.
  expect((await (await put(winner, 1)).json()).draft.version).toBe(2);
  check("different simultaneous saves yield one success/one conflict; lost-response retry retains version");
  expect((await get(otherToken)).status).toBe(404);
  expect((await put(proposal, 0, otherToken)).status).toBe(404);
  expect((await bearerClient(otherToken).from("follow_up_drafts").select("session_id").eq("session_id", note.session.id)).data).toEqual([]);
  const malformed = `${token.slice(0, -8)}invalid!`;
  expect((await get(malformed)).status).toBe(401);
  const anonymous = makeClient();
  expect((await anonymous.rpc("get_follow_up_draft", { p_session_id: note.session.id })).error?.code).toBe("42501");
  expect((await owner.from("follow_up_drafts").update({ version: 99 }).eq("session_id", note.session.id)).error?.code).toBe("42501");
  expect((await owner.from("follow_up_drafts").insert({ user_id: users[0].id, session_id: note.session.id, document: proposal })).error?.code).toBe("42501");
  expect((await owner.from("follow_up_drafts").delete().eq("session_id", note.session.id)).error?.code).toBe("42501");
  expect((await put({ ...winner, owner: users[1].id }, 2)).status).toBe(400);
  expect((await put({ ...winner, evidence: [{ kind: "note", id: "note", text: "Invented decision" }] }, 2)).status).toBe(400);
  check("other-owner, forged-token, anonymous, direct mutation and invalid evidence boundaries");
  const interrupted = { ...winner, fields: { ...winner.fields, body: "Interrupted synthetic update" } };
  const controller = new AbortController();
  const pending = owner.rpc("put_follow_up_draft", { p_session_id: note.session.id, p_document: interrupted, p_expected_version: 2 }).abortSignal(controller.signal);
  const attempt = Promise.resolve(pending); setTimeout(() => controller.abort(), 5); await attempt;
  // Abort can cancel transport after commit. A matching retry is the authoritative result.
  expect((await (await put(interrupted, 2)).json()).draft.version).toBe(3);
  check("aborted real RPC reconciles to one saved version through explicit identical retry");
  const reviewed = { ...interrupted, fields: { ...interrupted.fields, recipient: "sam@example.invalid" }, unknowns: [], reviewed: true };
  expect((await (await put(reviewed, 3)).json()).draft.version).toBe(4);
  const revisedNote = structuredClone(note); revisedNote.note = "Synthetic pilot paused. Confirm a new date.";
  const raceDraft = { ...reviewed, fields: { ...reviewed.fields, body: "Wording racing the source update" } };
  const sourceWrite = owner.rpc("put_session", { p_document: revisedNote, p_expected_version: 1, p_deleted: false });
  const [source, raced] = await Promise.all([sourceWrite, put(raceDraft, 4, secondSession)]);
  expect(source.error).toBeNull(); expect(source.data.version).toBe(2);
  expect([200, 409]).toContain(raced.status);
  const snapshot = await (await get()).json();
  expect(snapshot.sourceVersion).toBe(2); expect(snapshot.sourceChanged).toBe(true); expect(snapshot.draft.document.reviewed).toBe(false);
  expect((await put(reviewed, snapshot.draft.version)).status).toBe(409);
  check("simultaneous source/write cannot retain current approval; stale save refuses overwrite");
  const direct = await owner.from("sessions").update({ document: note, version: 1 }).eq("id", note.session.id).eq("user_id", users[0].id).select("version").single();
  expect(direct.error).toBeNull(); expect(direct.data!.version).toBe(3);
  expect((await (await get()).json()).draft.document.reviewed).toBe(false);
  check("direct source revert advances revision and cannot revive approval");
});
