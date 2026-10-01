import { afterEach, describe, expect, it, vi } from "vitest";
import { google, GoogleError } from "../src/lib/google";
afterEach(() => vi.unstubAllGlobals());
describe("Google Calendar recovery", () => {
  it.each([
    [403, "rateLimitExceeded", "usage limit"],
    [403, "userRateLimitExceeded", "usage limit"],
    [403, "quotaExceeded", "usage limit"],
    [429, "", "usage limit"],
    [403, "forbiddenForNonOrganizer", "organiser"],
    [403, "insufficientPermissions", "permissions"],
    [401, "authError", "could not verify"],
    [403, "unknownReason", "calendar sharing"],
    [412, "conditionNotMet", "changed in another app"],
  ])("uses actionable recovery for %s/%s without asserting revoked consent", async (status, reason, message) => {
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({error:{errors:[{reason}]}}, {status: Number(status)})));
    const error = await google("synthetic-token").calendars().catch(error => error);
    expect(error).toBeInstanceOf(GoogleError);
    expect(error.message).toContain(message);
    expect(error.message).not.toContain("revoked");
    expect(error.status).toBe(status);
  });
  it("preserves the provider status when the error body is not JSON", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("upstream unavailable", {status:503})));
    await expect(google("synthetic-token").calendars()).rejects.toMatchObject({status:503,message:"Google Calendar did not respond. Try again shortly."});
  });
});
