import { afterEach, describe, expect, it, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { createBookingPreviewRequest } from "../src/lib/scheduling/preview";
import { BookingRow, TypeEditor } from "../src/app/scheduling/scheduling";

const panels = vi.hoisted(() => ({ requests: [] as Array<(body?: unknown) => Promise<unknown>> }));
vi.mock("../src/components/messages", () => ({
  Messages: (props: { request: (body?: unknown) => Promise<unknown>; previewMode: boolean }) => {
    expect(props.previewMode).toBe(true);
    panels.requests.push(props.request);
    return null;
  },
  FollowUp: (props: { request: (body?: unknown) => Promise<unknown> }) => {
    panels.requests.push(props.request);
    return null;
  },
}));

afterEach(() => { vi.restoreAllMocks(); panels.requests.length = 0; });

describe("nested booking preview transport wiring", () => {
  it("keeps the meeting-type editor's Messages panel on the supplied transport", async () => {
    const fetch = vi.spyOn(globalThis, "fetch").mockRejectedValue(Error("Live API forbidden"));
    const request = createBookingPreviewRequest(), data = await request("/api/scheduling", "GET");
    renderToStaticMarkup(createElement(TypeEditor, { context: data, defaultAvailability: data.profile, value: data.types[0], request, previewMode: true, onCancel() {}, onSaved() {} }));
    expect(panels.requests).toHaveLength(1);
    expect(await panels.requests[0]()).toEqual({ settings: null, senders: [], rules: [], messages: [] });
    await expect(panels.requests[0]({ action: "rule" })).rejects.toThrow("Saving is unavailable");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("keeps a booking-row follow-up on the same isolated transport", async () => {
    const fetch = vi.spyOn(globalThis, "fetch").mockRejectedValue(Error("Live API forbidden"));
    const request = createBookingPreviewRequest(), data = await request("/api/scheduling", "GET");
    renderToStaticMarkup(createElement(BookingRow, { booking: data.bookings[0], request, previewMode: true, onCancelled() {} }));
    expect(panels.requests).toHaveLength(1);
    await expect(panels.requests[0]({ action: "draft", booking_id: data.bookings[0].id })).rejects.toThrow("Saving is unavailable");
    expect(fetch).not.toHaveBeenCalled();
  });
});
