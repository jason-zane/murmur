import { beforeEach, describe, expect, it, vi } from "vitest";
const auth = vi.hoisted(() => ({ user: "mac-owner", fail: false }));
vi.mock("../src/lib/http", async importOriginal => {
  const actual = await importOriginal<typeof import("../src/lib/http")>();
  return { ...actual, requireEditor: vi.fn(async () => { if (auth.fail) throw new actual.HttpError(401, "Sign in"); return { user: { id: auth.user } }; }) };
});
vi.mock("next/headers", () => ({ cookies: async () => ({ set: vi.fn() }) }));
import { GET } from "../src/app/api/google/connect/route";
describe("Google connection browser handoff", () => {
  beforeEach(() => { auth.fail = false; auth.user = "mac-owner"; vi.stubEnv("NEXT_PUBLIC_SITE_URL", "https://notes.example"); vi.stubEnv("GOOGLE_CLIENT_ID", "test-client"); vi.stubEnv("GOOGLE_CLIENT_SECRET", "test-secret"); });
  it("returns a signed-out browser to the intended Gmail connection after login", async () => {
    auth.fail = true;
    const r = await GET(new Request("https://notes.example/api/google/connect?inbox=1&expected_user=mac-owner"));
    const target = new URL(r.headers.get("location")!);
    expect(target.pathname).toBe("/login");
    expect(target.searchParams.get("next")).toBe("/api/google/connect?inbox=1&expected_user=mac-owner");
  });
  it("does not authorise Google for a different browser account", async () => {
    auth.user = "another-owner";
    const r = await GET(new Request("https://notes.example/api/google/connect?inbox=1&expected_user=mac-owner"));
    const target = new URL(r.headers.get("location")!);
    expect(target.pathname).toBe("/connections");
    expect(target.searchParams.get("error")).toContain("different Concourse account");
  });
  it("continues to Google for the matching account", async () => {
    const r = await GET(new Request("https://notes.example/api/google/connect?inbox=1&expected_user=mac-owner"));
    const target = new URL(r.headers.get("location")!);
    expect(target.hostname).toBe("accounts.google.com");
    expect(target.searchParams.get("scope")).toContain("gmail.modify");
    expect(target.searchParams.get("scope")).not.toContain("calendar");
  });
});
