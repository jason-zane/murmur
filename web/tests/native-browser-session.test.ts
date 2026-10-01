import { beforeEach, describe, expect, it, vi } from "vitest";
const auth = vi.hoisted(() => ({ verify: vi.fn(), getUser: vi.fn(), signOut: vi.fn() }));
vi.mock("../src/lib/supabase/server", () => ({ serverClient: async () => ({ auth: { verifyOtp: auth.verify, getUser: auth.getUser, signOut: auth.signOut } }), adminClient: vi.fn() }));
vi.mock("../src/lib/http", () => ({ requireEditor: vi.fn(), failure: vi.fn(), HttpError: class extends Error {} }));
import { GET } from "../src/app/api/native/session/route";
describe("Mac to browser session exchange", () => {
 beforeEach(() => { vi.clearAllMocks(); auth.getUser.mockResolvedValue({data:{user:null}}); vi.stubEnv("NEXT_PUBLIC_SITE_URL", "https://notes.example"); auth.verify.mockResolvedValue({ data: { user: { id: "owner" }, session: {} }, error: null }); });
 it("exchanges a one-use token before continuing Google setup with no caching or referrer", async () => {
  const r = await GET(new Request("https://notes.example/api/native/session?token_hash=one-use&user=owner&next=%2Fapi%2Fgoogle%2Fconnect%3Fadd%3D1"));
  expect(auth.verify).toHaveBeenCalledWith({type:"email",token_hash:"one-use"});
  expect(r.headers.get("location")).toBe("https://notes.example/api/google/connect?add=1");
  expect(r.headers.get("cache-control")).toBe("no-store");
  expect(r.headers.get("referrer-policy")).toBe("no-referrer");
 });
 it("rejects identity mismatches and clears the created session", async () => {
  const r = await GET(new Request("https://notes.example/api/native/session?token_hash=one-use&user=another&next=%2Fapi%2Fgoogle%2Fconnect"));
  expect(new URL(r.headers.get("location")!).pathname).toBe("/login");
  expect(auth.signOut).toHaveBeenCalledWith({scope:"local"});
 });
 it("rejects external destinations before consuming a token", async () => {
  await GET(new Request("https://notes.example/api/native/session?token_hash=one-use&user=owner&next=https%3A%2F%2Fevil.invalid"));
  expect(auth.verify).not.toHaveBeenCalled();
 });
 it("does not replace another signed-in browser account", async () => {
  auth.getUser.mockResolvedValue({data:{user:{id:"other"}}});
  const r = await GET(new Request("https://notes.example/api/native/session?token_hash=one-use&user=owner&next=%2Fapi%2Fgoogle%2Fconnect"));
  expect(new URL(r.headers.get("location")!).pathname).toBe("/connections");
  expect(auth.verify).not.toHaveBeenCalled();
 });
 it("rejects an expired or already consumed link", async () => {
  auth.verify.mockResolvedValue({data:{user:null,session:null},error:{message:"expired"}});
  const r = await GET(new Request("https://notes.example/api/native/session?token_hash=old&user=owner&next=%2Fapi%2Fgoogle%2Fconnect"));
  expect(new URL(r.headers.get("location")!).pathname).toBe("/login");
 });
});
