import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { READ_SCOPES, SCOPE } from "../src/lib/google";
const fixture = vi.hoisted(() => ({
  records: [] as Record<string, any>[],
  stored: "", set: vi.fn(), delete: vi.fn(), save: vi.fn(), token: vi.fn(), refresh: vi.fn(),
}));
afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
vi.mock("../src/lib/supabase/server", () => ({ serverClient: vi.fn(), bearerClient: vi.fn(), adminClient: vi.fn() }));
const client = {
  from: () => {
    const filters: [string, unknown][] = [];
    const query = {select: () => query, eq: (key: string, value: unknown) => { filters.push([key,value]); return query; },
      maybeSingle: async () => ({data: fixture.records.find(record => filters.every(([key,value]) => record[key] === value)) ?? null,error:null})};
    return query;
  },
};
vi.mock("../src/lib/http", async importOriginal => {
  const actual = await importOriginal<typeof import("../src/lib/http")>();
  return {...actual, requireEditor: vi.fn(async () => ({user:{id:"owner"},client})), requestAuth: vi.fn(async () => ({user:{id:"owner"},client}))};
});
vi.mock("next/headers", () => ({cookies: async () => ({set:fixture.set,delete:fixture.delete,get:() => fixture.stored ? {value:fixture.stored} : undefined})}));
vi.mock("../src/lib/calendar", () => ({googleToken:fixture.token,saveConnection:fixture.save,connectionsFor:async()=>[],refreshConnection:fixture.refresh}));
import { GET as connect } from "../src/app/api/google/connect/route";
import { GET as callback } from "../src/app/api/google/callback/route";
const id = "00000000-0000-4000-8000-000000000001";
const record = () => ({id,user_id:"owner",provider:"google",email:"host@example.com",provider_subject:"google-host",scopes:[...READ_SCOPES]});
const request = (query: string) => new Request(`https://notes.example/api/google/connect?${query}`);
const location = (r: Response) => new URL(r.headers.get("location")!);
async function begin() {
  await connect(request(`reconnect=${id}`));
  fixture.stored = fixture.set.mock.calls[0][1];
}
async function finish(code = "code") {
  const state = JSON.parse(fixture.stored).state;
  return callback(new Request(`https://notes.example/api/google/callback?state=${state}${code ? `&code=${code}` : ""}`));
}
beforeEach(() => {
  vi.clearAllMocks(); fixture.records=[record()]; fixture.stored="";
  fixture.delete.mockImplementation(() => { fixture.stored=""; });
  vi.stubEnv("NEXT_PUBLIC_SITE_URL","https://notes.example");vi.stubEnv("GOOGLE_CLIENT_ID","test-client");vi.stubEnv("GOOGLE_CLIENT_SECRET","test-secret");
  fixture.token.mockResolvedValue({access_token:"synthetic-token",scope:READ_SCOPES.join(" "),refresh_token:"synthetic-refresh"});
  fixture.save.mockResolvedValue(id);
  vi.stubGlobal("fetch",vi.fn(async()=>Response.json({sub:"google-host",email:"host@example.com",email_verified:true})));
});
describe("same-account Google reconnection", () => {
  it("requests only recorded scopes despite permission-expansion query flags", async () => {
    fixture.records[0].scopes = ["openid","email","https://www.googleapis.com/auth/gmail.modify"];
    const target=location(await connect(request(`reconnect=${id}&booking=1&mail=1&add=1&account=other@example.com`)));
    expect(target.searchParams.get("scope")?.split(" ")).toEqual(fixture.records[0].scopes);
    expect(target.searchParams.get("include_granted_scopes")).toBe("false");
    expect(target.searchParams.get("login_hint")).toBe("host@example.com");
    expect(JSON.parse(fixture.set.mock.calls[0][1])).toMatchObject({reconnectID:id,booking:false,mail:false,inbox:false});
  });
  it.each(["another-owner", "another-provider"])("rejects an account outside the owner/provider scope (%s)", async mode => {
    if(mode==="another-owner")fixture.records[0].user_id="other";else fixture.records[0].provider="other";
    expect((await connect(request(`reconnect=${id}`))).status).toBe(404);
    expect(fixture.set).not.toHaveBeenCalled();
  });
  it("does not use a caller-supplied email when the stored identity has no email", async () => {
    fixture.records[0].email=null;
    const target=location(await connect(request(`reconnect=${id}&account=other@example.com`)));
    expect(target.searchParams.has("login_hint")).toBe(false);
  });
  it("cancelling does not exchange or save credentials", async () => {
    await begin(); const target=location(await finish(""));
    expect(target.searchParams.get("error")).toContain("cancelled");
    expect(fixture.token).not.toHaveBeenCalled();expect(fixture.save).not.toHaveBeenCalled();
  });
  it("rejects a changed OAuth state without exchanging credentials", async () => {
    await begin();const r=await callback(new Request("https://notes.example/api/google/callback?state=wrong&code=code"));
    expect(location(r).searchParams.get("error")).toContain("expired");expect(fixture.token).not.toHaveBeenCalled();
  });
  it("a repeated callback cannot save the same connection twice", async () => {
    await begin();const state=JSON.parse(fixture.stored).state;
    const r = () => new Request(`https://notes.example/api/google/callback?state=${state}&code=code`);
    await callback(r());expect(location(await callback(r())).searchParams.get("error")).toContain("expired");
    expect(fixture.save).toHaveBeenCalledOnce();expect(fixture.token).toHaveBeenCalledOnce();
  });
  it("rejects selecting a different Google identity even with the same email", async () => {
    await begin();vi.stubGlobal("fetch",vi.fn(async()=>Response.json({sub:"other-google",email:"host@example.com",email_verified:true})));
    expect(location(await finish()).searchParams.get("error")).toContain("same Google account");
    expect(fixture.save).not.toHaveBeenCalled();
  });
  it("rejects partial consent before changing the existing connection", async () => {
    await begin();fixture.token.mockResolvedValue({access_token:"synthetic-token",scope:`openid email ${SCOPE.eventsRead}`});
    expect(location(await finish()).searchParams.get("error")).toContain("existing access");expect(fixture.save).not.toHaveBeenCalled();
  });
  it("rejects an account removed while consent was open", async () => {
    await begin();fixture.records=[];expect(location(await finish()).searchParams.get("error")).toContain("no longer linked");
    expect(fixture.token).not.toHaveBeenCalled();expect(fixture.save).not.toHaveBeenCalled();
  });
  it("restores the same connection and returns to Connected apps", async () => {
    await begin();const target=location(await finish());
    expect(fixture.save).toHaveBeenCalledWith("owner","host@example.com",READ_SCOPES,"synthetic-refresh","google-host");
    expect(target.pathname).toBe("/connections");expect(target.searchParams.get("error")).toBeNull();
  });
  it("recovers a legacy email identity with case-insensitive verified email", async () => {
    fixture.records[0].provider_subject=null;fixture.records[0].email="HOST@example.com";await begin();await finish();
    expect(fixture.save).toHaveBeenCalledOnce();
  });
});
