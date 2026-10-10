import { afterEach, describe, expect, it, vi } from "vitest";
import { AvailabilityRequest } from "../src/lib/scheduling/availability-request";

afterEach(() => vi.unstubAllGlobals());
const response = (slots: string[]) => new Response(JSON.stringify({ slots }));
describe("guest availability request lifecycle", () => {
  it("ignores an older response even if the provider ignores cancellation", async () => {
    let finishOld!: (response: Response) => void;
    const fetcher = vi.fn().mockImplementationOnce(() => new Promise(resolve => { finishOld = resolve; }))
      .mockResolvedValueOnce(response(["2026-11-02T10:00:00Z"]));
    vi.stubGlobal("fetch", fetcher);
    const request = new AvailabilityRequest();
    const old = request.load("/october");
    expect(await request.load("/november")).toEqual({ slots: ["2026-11-02T10:00:00Z"] });
    expect(fetcher.mock.calls[0][1].signal.aborted).toBe(true);
    finishOld(response(["2026-10-02T10:00:00Z"]));
    expect(await old).toBeNull();
  });
  it("cancels on navigation and suppresses late failures", async () => {
    let fail!: (error: Error) => void;
    vi.stubGlobal("fetch", vi.fn(() => new Promise((_, reject) => { fail = reject; })));
    const request = new AvailabilityRequest();
    const pending = request.load("/calendar");
    request.cancel();
    fail(new Error("Provider unavailable"));
    expect(await pending).toBeNull();
  });
  it("allows repeated recovery after failure without treating empty availability as an error", async () => {
    vi.stubGlobal("fetch", vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: "Calendar unavailable" }), { status: 503 }))
      .mockResolvedValueOnce(response([]))
      .mockResolvedValueOnce(response(["2026-10-02T10:00:00Z"])));
    const request = new AvailabilityRequest();
    expect(await request.load("/calendar")).toEqual({ error: "Calendar unavailable" });
    expect(await request.load("/calendar")).toEqual({ slots: [] });
    expect(await request.load("/calendar")).toEqual({ slots: ["2026-10-02T10:00:00Z"] });
  });
  it("rejects malformed availability instead of crashing the calendar", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response(["invalid"])));
    expect(await new AvailabilityRequest().load("/calendar")).toEqual({ error: "Open times couldn’t be loaded. Try again." });
  });
});
