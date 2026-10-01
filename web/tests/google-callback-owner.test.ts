import { beforeEach, describe, expect, it, vi } from "vitest";
const flow = vi.hoisted(() => ({ user: "original-owner", stored: "", token: vi.fn(), save: vi.fn() }));
vi.mock("../src/lib/http", () => ({ requestAuth: async () => ({ user: { id: flow.user } }) }));
vi.mock("next/headers", () => ({ cookies: async () => ({ get: () => ({ value: flow.stored }), delete: vi.fn() }) }));
vi.mock("../src/lib/calendar", () => ({ googleToken: flow.token, saveConnection: flow.save, connectionsFor: vi.fn(), refreshConnection: vi.fn() }));
vi.mock("../src/lib/supabase/server", () => ({ adminClient: vi.fn() }));
import { GET } from "../src/app/api/google/callback/route";
describe("Google callback account ownership", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv("NEXT_PUBLIC_SITE_URL", "https://notes.example");
    flow.user = "original-owner";
    flow.stored = JSON.stringify({ state: "valid-state", verifier: "verifier", userID: "original-owner", inbox: true });
  });
  it("rejects an account switch before exchanging or saving the Google grant", async () => {
    flow.user = "another-owner";
    const response = await GET(new Request("https://notes.example/api/google/callback?state=valid-state&code=code"));
    expect(new URL(response.headers.get("location")!).searchParams.get("error")).toContain("account changed");
    expect(flow.token).not.toHaveBeenCalled();
    expect(flow.save).not.toHaveBeenCalled();
  });
  it("requires a fresh connection for cookies created before ownership binding", async () => {
    flow.stored = JSON.stringify({ state: "valid-state", verifier: "verifier" });
    const response = await GET(new Request("https://notes.example/api/google/callback?state=valid-state&code=code"));
    expect(new URL(response.headers.get("location")!).searchParams.get("error")).toContain("Restart");
    expect(flow.token).not.toHaveBeenCalled();
    expect(flow.save).not.toHaveBeenCalled();
  });
});
