import { describe, expect, it, vi } from "vitest";
vi.mock("../src/lib/supabase/server", () => ({
  bearerClient: (token: string) => ({
    auth: {
      getClaims: async () => ({
        data:
          token === "invalid"
            ? null
            : {
                claims: {
                  sub: "user-fixture",
                  client_id: "ai-app-fixture",
                  iss: "https://fixture.supabase.co/auth/v1",
                  aud:
                    token === "wrong-audience"
                      ? "authenticated"
                      : "https://fixture.murmur.test/mcp",
                },
              },
        error: token === "invalid" ? new Error("invalid") : null,
      }),
    },
  }),
}));
import { POST } from "../src/app/mcp/route";
process.env.NEXT_PUBLIC_SITE_URL = "https://fixture.murmur.test";
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://fixture.supabase.co";
process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "fixture-publishable-key";
function request(method: string, token?: string, params?: unknown) {
  return new Request("https://fixture.murmur.test/mcp", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method,
      ...(params ? { params } : {}),
    }),
  });
}
describe("remote MCP transport and authorization", () => {
  it("challenges unauthenticated requests with OAuth resource discovery", async () => {
    const result = await POST(request("tools/list"));
    expect(result.status).toBe(401);
    expect(result.headers.get("www-authenticate")).toContain(
      "/.well-known/oauth-protected-resource/mcp",
    );
  });
  it.each(["invalid", "wrong-audience"])("rejects %s tokens", async (token) => {
    expect((await POST(request("tools/list", token))).status).toBe(401);
  });
  it("negotiates the standard MCP wire protocol", async () => {
    const r = await POST(
      request("initialize", "valid", {
        protocolVersion: "2025-11-25",
        capabilities: {},
        clientInfo: { name: "test-client", version: "1" },
      }),
    );
    expect(r.status).toBe(200);
    const body = await r.json();
    expect(body.result.serverInfo.name).toBe("murmur");
    expect(body.result.protocolVersion).toBe("2025-11-25");
  });
  it("advertises read-only tools including search, fetch and upcoming meetings", async () => {
    const r = await POST(request("tools/list", "valid"));
    expect(r.status).toBe(200);
    const body = await r.json();
    expect(body.result.tools.map((t: { name: string }) => t.name)).toEqual(
      expect.arrayContaining([
        "search",
        "fetch",
        "get_transcript",
        "list_upcoming_meetings",
        "list_booking_links",
        "list_bookings",
        "find_free_time",
      ]),
    );
    expect(
      body.result.tools.every(
        (t: { annotations: { readOnlyHint: boolean } }) =>
          t.annotations.readOnlyHint,
      ),
    ).toBe(true);
    expect(
      body.result.tools.some(
        (t: { name: string }) => t.name === "save_summary",
      ),
    ).toBe(false);
  });
  it("refuses unrecognized browser origins", async () => {
    const req = request("tools/list", "valid");
    req.headers.set("Origin", "https://untrusted.example");
    expect((await POST(req)).status).toBe(403);
  });
});
