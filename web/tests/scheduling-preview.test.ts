import { afterEach, describe, expect, it, vi } from "vitest";
import { createBookingPreviewRequest } from "../src/lib/scheduling/preview";
import { schedulingRequest, selectSchedulingRequest } from "../src/lib/scheduling/request";

afterEach(() => vi.restoreAllMocks());

describe("synthetic booking transport boundary", () => {
  it("loads only fixed synthetic data and cannot contact authenticated APIs", async () => {
    const fetch = vi.spyOn(globalThis, "fetch").mockRejectedValue(Error("Live network forbidden"));
    const request = createBookingPreviewRequest();
    const data = await request("/api/scheduling", "GET");
    expect(data.accounts[0].id).toBe("synthetic-calendar");
    expect(data.accounts[0].email).toBe("sam@example.invalid");
    expect(data.base_url).toBe("https://example.invalid/book");
    expect(await request("/api/messages", "GET")).toEqual({ settings: null, senders: [], rules: [], messages: [] });
    expect(fetch).not.toHaveBeenCalled();
  });

  it.each([
    ["/api/scheduling", "PUT"], ["/api/scheduling/event-types", "POST"],
    ["/api/scheduling/event-types/synthetic-intro", "PATCH"], ["/api/scheduling/event-types/synthetic-intro", "DELETE"],
    ["/api/scheduling/availability", "POST"], ["/api/scheduling/availability?id=sample", "DELETE"],
    ["/api/scheduling/bookings/sample", "POST"], ["/api/scheduling/bookings/sample", "DELETE"],
    ["/api/messages", "POST"], ["/api/google/connect", "GET"],
    ["https://example.com/api/scheduling", "GET"], ["/api/scheduling?owner=real", "GET"],
  ])("refuses %s %s without any live fallback, including retries", async (url, method) => {
    const fetch = vi.spyOn(globalThis, "fetch").mockRejectedValue(Error("Live network forbidden"));
    const request = selectSchedulingRequest(true, createBookingPreviewRequest());
    for (let attempt = 0; attempt < 2; attempt++) {
      await expect(request(url, method, { action: "cancel", title: "Unsaved edit" })).rejects.toThrow("unavailable");
    }
    expect(fetch).not.toHaveBeenCalled();
  });

  it("fails closed when a preview transport is omitted", async () => {
    const fetch = vi.spyOn(globalThis, "fetch").mockRejectedValue(Error("Live network forbidden"));
    const request = selectSchedulingRequest(true);
    await expect(request("/api/scheduling", "GET")).rejects.toThrow("No live request");
    await expect(request("/api/scheduling", "PUT", {})).rejects.toThrow("No live request");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("returns independent data and preserves fixture state after failed edits", async () => {
    const fetch = vi.spyOn(globalThis, "fetch").mockRejectedValue(Error("Live network forbidden"));
    const request = createBookingPreviewRequest();
    const data = await request("/api/scheduling", "GET");
    data.profile.display_name = "Changed locally";
    data.types[0].active = false;
    await expect(request("/api/scheduling", "PUT", data.profile)).rejects.toThrow("edits remain open");
    const reloaded = await request("/api/scheduling", "GET");
    expect(reloaded.profile.display_name).toBe("Sam Example");
    expect(reloaded.types[0].active).toBe(true);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("retains the authenticated transport for the actual owner workspace", async () => {
    const fetch = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({ saved: true }), {status: 200}));
    const request = selectSchedulingRequest(false);
    expect(request).toBe(schedulingRequest);
    expect(await request("/api/scheduling", "PUT", { display_name: "Owner" })).toEqual({ saved: true });
    expect(fetch).toHaveBeenCalledWith("/api/scheduling", {
      method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ display_name: "Owner" }),
    });
  });
});
