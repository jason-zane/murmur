import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { FOLLOW_UP_RECIPE, followUpDocument } from "../src/lib/follow-up/drafts";
import { siteURL } from "../src/lib/config";

const transport = vi.hoisted(() => ({
  rpc: vi.fn(),
  getUser: vi.fn(),
  cookieClient: vi.fn(),
  bearerClient: vi.fn(),
}));
// Mock only the Auth/database transport. Real requestAuth, requireEditor,
// body limits, validation, routing and response mapping execute below.
vi.mock("../src/lib/supabase/server", () => ({
  serverClient: transport.cookieClient,
  bearerClient: transport.bearerClient,
}));
import { GET, PUT } from "../src/app/api/sessions/[id]/follow-up/route";
const context = { params: Promise.resolve({ id: "synthetic-note" }) };
const document = () => ({
  sourceVersion: 1, recipe: FOLLOW_UP_RECIPE,
  fields: { recipient: "", subject: "Pilot follow-up", body: "Start a small pilot." },
  evidence: [{ kind: "note" as const, id: "note", text: "Start a small pilot." }],
  unknowns: ["Recipient is missing."], reviewed: false,
});
function request(method: string, body?: unknown, headers: Record<string, string> = { authorization: "Bearer synthetic-owner" }) {
  return new Request("http://localhost/api/sessions/synthetic-note/follow-up", {
    method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}
beforeEach(() => {
  vi.resetAllMocks();
  vi.stubEnv("FOLLOW_UP_DRAFTS_ENABLED", "true");
  const client = { auth: { getUser: transport.getUser }, rpc: transport.rpc };
  transport.cookieClient.mockResolvedValue(client);
  transport.bearerClient.mockReturnValue(client);
  transport.getUser.mockResolvedValue({ data: { user: { id: "synthetic-owner" } }, error: null });
  transport.rpc.mockImplementation(async (name: string, args: { p_document?: unknown }) => {
    if (name === "is_murmur_editor") return { data: true, error: null };
    if (name === "get_follow_up_draft") return { data: { draft: null, sourceVersion: 1 }, error: null };
    return { data: { session_id: "synthetic-note", version: 1, document: args.p_document, updated_at: "2026-10-01T00:00:00Z" }, error: null };
  });
});
afterEach(() => vi.unstubAllEnvs());
describe("authenticated follow-up draft HTTP contract", () => {
  it.each([undefined, "false", "", "TRUE"])("gates GET and PUT before Auth/RPC when the flag is %s", async value => {
    vi.stubEnv("FOLLOW_UP_DRAFTS_ENABLED", value);
    for (const method of ["GET", "PUT"]) {
      const response = await (method === "GET" ? GET(request(method), context) : PUT(request(method, { document: document(), expectedVersion: 0 }), context));
      expect(response.status).toBe(404);
      expect(response.headers.get("cache-control")).toBe("private, no-store");
    }
    expect(transport.getUser).not.toHaveBeenCalled();
    expect(transport.cookieClient).not.toHaveBeenCalled();
    expect(transport.bearerClient).not.toHaveBeenCalled();
    expect(transport.rpc).not.toHaveBeenCalled();
  });
  it("loads a consistent snapshot without fetching the private source text", async () => {
    const response = await GET(request("GET"), context);
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(await response.json()).toEqual({ draft: null, sourceVersion: 1, sourceChanged: false });
    expect(transport.rpc).toHaveBeenLastCalledWith("get_follow_up_draft", { p_session_id: "synthetic-note" });
  });
  it("saves incomplete edits with no owner or dispatch fields supplied to the RPC", async () => {
    const proposal = document();
    proposal.fields.recipient = "sam@";
    const response = await PUT(request("PUT", { document: proposal, expectedVersion: 0 }), context);
    expect(response.status).toBe(200);
    expect((await response.json()).draft.document).toEqual(proposal);
    expect(transport.rpc).toHaveBeenLastCalledWith("put_follow_up_draft", { p_session_id: "synthetic-note", p_document: proposal, p_expected_version: 0 });
    expect(transport.rpc.mock.calls.every(([name]) => ["is_murmur_editor", "put_follow_up_draft"].includes(name))).toBe(true);
  });
  it("removes effective approval from stale sources while keeping saved wording and lineage", async () => {
    const saved = { session_id: "synthetic-note", version: 3, document: { ...document(), reviewed: true }, updated_at: "2026-10-01T00:00:00Z" };
    transport.rpc.mockImplementation(async name => ({ data: name === "is_murmur_editor" ? true : { draft: saved, sourceVersion: 2 }, error: null }));
    const response = await GET(request("GET"), context), result = await response.json();
    expect(result.sourceChanged).toBe(true);
    expect(result.draft.document).toEqual({ ...saved.document, reviewed: false });
    expect(saved.document.reviewed).toBe(true); // Read does not mutate the saved recovery record.
    expect(result.draft.version).toBe(3);
  });
  it("rejects unauthenticated, forged and connected-AI requests before draft access", async () => {
    transport.getUser.mockResolvedValueOnce({ data: { user: null }, error: Error("Invalid token") });
    expect((await GET(request("GET", undefined, { authorization: "Bearer forged" }), context)).status).toBe(401);
    expect(transport.rpc).not.toHaveBeenCalled();
    transport.rpc.mockResolvedValue({ data: false, error: null });
    expect((await PUT(request("PUT", { document: document(), expectedVersion: 0 }), context)).status).toBe(403);
    expect(transport.rpc.mock.calls.map(([name]) => name)).toEqual(["is_murmur_editor"]);
  });
  it("rejects cross-origin cookie writes using the real CSRF boundary", async () => {
    const response = await PUT(request("PUT", { document: document(), expectedVersion: 0 }, { origin: "https://hostile.example.invalid" }), context);
    expect(response.status).toBe(403);
    expect(transport.rpc).not.toHaveBeenCalled();
  });
  it("accepts verified first-party cookie writes from the configured app origin", async () => {
    const response = await PUT(request("PUT", { document: document(), expectedVersion: 0 }, { origin: siteURL() }), context);
    expect(response.status).toBe(200);
    expect(transport.getUser).toHaveBeenCalledWith();
  });
  it("rejects owner injection, send instructions, unknown recipes and unsafe source IDs", async () => {
    for (const payload of [
      { document: document(), expectedVersion: 0, user_id: "other" },
      { document: { ...document(), provider: "new-provider" }, expectedVersion: 0 },
      { document: { ...document(), fields: { ...document().fields, send: true } }, expectedVersion: 0 },
      { document: { ...document(), recipe: "send/v1" }, expectedVersion: 0 },
    ]) expect((await PUT(request("PUT", payload), context)).status).toBe(400);
    expect((await PUT(request("PUT", { document: document(), expectedVersion: 0 }), { params: Promise.resolve({ id: "../other" }) })).status).toBe(400);
    expect(transport.rpc.mock.calls.every(([name]) => name === "is_murmur_editor")).toBe(true);
  });
  it("limits streamed bodies and returns a recoverable JSON error", async () => {
    const response = await PUT(request("PUT", { extra: "x".repeat(100001) }), context);
    expect(response.status).toBe(413);
    const malformed = new Request("http://localhost/api", { method: "PUT", headers: { authorization: "Bearer synthetic-owner" }, body: "{" });
    expect((await PUT(malformed, context)).status).toBe(400);
    expect(transport.rpc.mock.calls.every(([name]) => name === "is_murmur_editor")).toBe(true);
  });
  it.each([["PT409", 409], ["PT404", 404], ["42501", 403], ["22023", 400]])("maps database %s without automatic retries", async (code, status) => {
    transport.rpc.mockImplementation(async name => name === "is_murmur_editor" ? { data: true, error: null } : { data: null, error: { code } });
    const response = await PUT(request("PUT", { document: document(), expectedVersion: 1 }), context);
    expect(response.status).toBe(status);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(typeof (await response.json()).error).toBe("string");
    expect(transport.rpc.mock.calls.filter(([name]) => name === "put_follow_up_draft")).toHaveLength(1);
  });
  it("returns an unavailable note without disclosing another owner's draft", async () => {
    transport.rpc.mockImplementation(async name => ({ data: name === "is_murmur_editor" ? true : null, error: null }));
    expect((await GET(request("GET"), context)).status).toBe(404);
  });
});

describe("reviewable draft schema", () => {
  it("requires confirmed details before approval while allowing durable incomplete work", () => {
    expect(followUpDocument.safeParse(document()).success).toBe(true);
    expect(followUpDocument.safeParse({ ...document(), fields: { ...document().fields, recipient: "sam@" } }).success).toBe(true);
    expect(followUpDocument.safeParse({ ...document(), reviewed: true }).success).toBe(false);
    const reviewed = { ...document(), reviewed: true, unknowns: [], fields: { ...document().fields, recipient: "sam@example.invalid" } };
    expect(followUpDocument.safeParse(reviewed).success).toBe(true);
    for (const patch of [{ evidence: [] }, { fields: { ...reviewed.fields, subject: " " } }, { fields: { ...reviewed.fields, recipient: "sam@example.invalid\nBcc: other@example.invalid" } }, { evidence: [...reviewed.evidence, ...reviewed.evidence] }])
      expect(followUpDocument.safeParse({ ...reviewed, ...patch }).success).toBe(false);
  });
});
