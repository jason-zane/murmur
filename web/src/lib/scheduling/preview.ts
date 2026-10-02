import type { SchedulingRequest } from "./request";

/** Fixed synthetic data only. No fetch, storage, credentials or live fallback. */
export function createBookingPreviewRequest(): SchedulingRequest {
  const booking = {
    title: "Synthetic intro call", guest_name: "Priya Example", guest_email: "priya@example.invalid",
    guest_time_zone: "Australia/Sydney", attendance: "unknown", answers: [], meeting_url: null,
  };
  const now = Date.now();
  const data = {
    schedules: [],
    profile: {
      handle: "concourse-design-sample", display_name: "Sam Example", time_zone: "Australia/Sydney",
      weekly_hours: [{ days: [1, 2, 3, 4, 5], start: "09:00", end: "17:00" }], date_overrides: [],
      destination_connection_id: "synthetic-calendar", destination_calendar_id: "primary",
    },
    types: [{
      id: "synthetic-intro", slug: "intro", title: "Intro call", description: "A synthetic meeting type for design review.",
      duration_minutes: 30, location_kind: "google_meet", location_detail: null, summary_template: "meeting", questions: [],
      minimum_notice_minutes: 120, buffer_before_minutes: 5, buffer_after_minutes: 5, slot_interval_minutes: 30,
      booking_window_days: 30, daily_limit: null, active: true, position: 0,
      email_connection_id: null, availability_schedule_id: null, availability_override: null,
      destination_connection_id: null, destination_calendar_id: null,
    }],
    bookings: [
      { ...booking, id: "synthetic-upcoming", status: "confirmed", starts_at: new Date(now + 86_400_000).toISOString(), ends_at: new Date(now + 88_200_000).toISOString() },
      { ...booking, id: "synthetic-past", status: "confirmed", starts_at: new Date(now - 88_200_000).toISOString(), ends_at: new Date(now - 86_400_000).toISOString() },
      { ...booking, id: "synthetic-cancelled", status: "cancelled", starts_at: new Date(now + 86_400_000).toISOString(), ends_at: new Date(now + 88_200_000).toISOString() },
    ],
    accounts: [{ id: "synthetic-calendar", email: "sam@example.invalid", can_book: true, can_send: false }],
    calendars: [{ connection_id: "synthetic-calendar", calendar_id: "primary", name: "Work calendar · synthetic", is_primary: true, can_write: true }],
    base_url: "https://example.invalid/book",
  };
  return async (url, method) => {
    if (method !== "GET") throw new Error("Saving is unavailable in the synthetic booking preview. Your edits remain open; no live changes were made.");
    if (url === "/api/scheduling") return structuredClone(data);
    if (url === "/api/messages") return { settings: null, senders: [], rules: [], messages: [] };
    throw new Error("This request is unavailable in the synthetic booking preview. No live request was made.");
  };
}
