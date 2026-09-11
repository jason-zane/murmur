import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { agenda, encryptToken } from "../src/lib/calendar";
import { BOOKING_SCOPES } from "../src/lib/google";
import {
  cancelBooking,
  createBooking,
  freeTimes,
  guestView,
  hashToken,
  rateLimit,
  rescheduleBooking,
  slotsFor,
} from "../src/lib/scheduling/booking";
import { POST as book } from "../src/app/api/book/[handle]/[slug]/route";

// Run only through scripts/test-integration.mjs, against the isolated local stack.
// Google is an in-memory calendar here: no request leaves this machine.
const api = process.env.NEXT_PUBLIC_SUPABASE_URL!;
if (api !== "http://127.0.0.1:56321") throw new Error("Integration tests require isolated local Murmur.");
process.env.GOOGLE_TOKEN_ENCRYPTION_KEY ||= randomBytes(32).toString("base64");
process.env.GOOGLE_CLIENT_ID ||= "integration-client";
process.env.GOOGLE_CLIENT_SECRET ||= "integration-secret";
const site = process.env.NEXT_PUBLIC_SITE_URL!;
const auth = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };
const admin = createClient(api, process.env.SUPABASE_SECRET_KEY!, { auth });

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Call = { method: string; url: URL; body?: Record<string, any> };
const calls: Call[] = [];
let googleBusy: { start: string; end: string }[] = [];
let failInsert = false;
const realFetch = globalThis.fetch;
vi.stubGlobal("fetch", async (input: string | URL | Request, init?: RequestInit) => {
  const url = new URL(input instanceof Request ? input.url : String(input));
  if (url.origin === "https://oauth2.googleapis.com")
    return Response.json({ access_token: "integration-access", expires_in: 3600, scope: BOOKING_SCOPES.join(" ") });
  if (url.origin !== "https://www.googleapis.com") return realFetch(input, init);
  const method = init?.method ?? "GET";
  const body = typeof init?.body === "string" ? JSON.parse(init.body) : undefined;
  calls.push({ method, url, body });
  if (url.pathname.endsWith("/freeBusy"))
    return Response.json({
      calendars: Object.fromEntries(body.items.map((i: { id: string }) => [i.id, { busy: googleBusy }])),
    });
  if (method === "POST") {
    if (failInsert) return Response.json({ error: "backendError" }, { status: 500 });
    return Response.json({ ...body, id: `event-${calls.length}`, hangoutLink: "https://meet.google.com/abc-defg-hij" });
  }
  if (method === "PATCH") return Response.json({ ...body, id: decodeURIComponent(url.pathname.split("/").pop()!) });
  if (method === "DELETE") return new Response(null, { status: 204 });
  return Response.json({ items: [] });
});

const must = <T,>(result: { data: T; error: unknown }) => {
  if (result.error) throw result.error;
  return result.data as NonNullable<T>;
};
const today = new Date();
const day = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() + 3));
const at = (h: number, m = 0) => new Date(day.getTime() + (h * 60 + m) * 60_000);
const iso = (h: number, m = 0) => at(h, m).toISOString();
const open = async () => (await slotsFor(handle, "intro", at(0), at(24), "UTC")).map((d) => d.toISOString());
const tokenOf = (url: string) => url.split("#")[1];
const guest = {
  name: "Ada Guest",
  email: "ada@example.invalid",
  time_zone: "Australia/Sydney",
  answers: { topic: "Pricing for a team of 12" },
};
const users: string[] = [];
let host: SupabaseClient, userID: string, handle: string, connectionID: string, typeID: string;
let first: Awaited<ReturnType<typeof createBooking>>;

async function createUser() {
  const email = `booking-${randomUUID()}@example.invalid`, password = randomBytes(24).toString("base64url");
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (created.error) throw created.error;
  users.push(created.data.user.id);
  const client = createClient(api, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, { auth });
  const signed = await client.auth.signInWithPassword({ email, password });
  if (signed.error) throw signed.error;
  return { id: created.data.user.id, client };
}

beforeAll(async () => {
  ({ id: userID, client: host } = await createUser());
  await createUser();
  handle = `it-${randomUUID().slice(0, 8)}`;
  connectionID = must(
    await admin
      .from("calendar_connections")
      .insert({ user_id: userID, provider: "google", email: "host@example.invalid", scopes: BOOKING_SCOPES })
      .select("id")
      .single(),
  ).id;
  must(
    await admin.from("calendar_credentials").insert({
      connection_id: connectionID,
      user_id: userID,
      encrypted_refresh_token: encryptToken("integration-refresh"),
    }),
  );
  must(
    await admin.from("calendar_sources").insert({
      connection_id: connectionID,
      user_id: userID,
      calendar_id: "primary",
      name: "Integration Host",
      is_primary: true,
      can_write: true,
      selected: true,
    }),
  );
  must(
    await admin.from("booking_profiles").insert({
      user_id: userID,
      handle,
      display_name: "Integration Host",
      time_zone: "UTC",
      weekly_hours: [{ days: [0, 1, 2, 3, 4, 5, 6], start: "00:00", end: "24:00" }],
      date_overrides: [],
      destination_connection_id: connectionID,
      destination_calendar_id: "primary",
    }),
  );
  typeID = must(
    await admin
      .from("event_types")
      .insert({
        user_id: userID,
        slug: "intro",
        title: "Intro call",
        duration_minutes: 30,
        location_kind: "google_meet",
        summary_template: "oneOnOne",
        questions: [{ id: "topic", label: "What would you like to cover?", required: true, long: true }],
        minimum_notice_minutes: 0,
        booking_window_days: 30,
      })
      .select("id")
      .single(),
  ).id;
});
afterAll(async () => {
  vi.unstubAllGlobals();
  for (const id of users) await admin.auth.admin.deleteUser(id);
});

describe("booking links against the host's own calendar", () => {
  it("offers only times that are free on every calendar, the Mac and existing bookings", async () => {
    googleBusy = [{ start: iso(10), end: iso(11) }];
    must(await admin.from("device_busy_times").upsert({ user_id: userID, blocks: [{ start: iso(18), end: iso(19) }] }));
    const slots = await open();
    expect(slots).toEqual(expect.arrayContaining([iso(9), iso(12), iso(20)]));
    for (const taken of [iso(10), iso(10, 30), iso(18), iso(18, 30)]) expect(slots).not.toContain(taken);
    expect(calls.some((c) => c.url.pathname.endsWith("/freeBusy"))).toBe(true);
  });

  it("books on the host's calendar so Google sends the invitation and Meet link", async () => {
    googleBusy = [];
    const before = calls.length;
    first = await createBooking(handle, "intro", { ...guest, start: iso(12) });
    expect(first.meeting_url).toBe("https://meet.google.com/abc-defg-hij");
    expect(first.manage_url.startsWith(`${site}/book/manage/${first.id}#`)).toBe(true);
    const insert = calls.slice(before).find((c) => c.method === "POST" && c.url.pathname.endsWith("/calendars/primary/events"))!;
    expect(insert.url.searchParams.get("sendUpdates")).toBe("all");
    expect(insert.url.searchParams.get("conferenceDataVersion")).toBe("1");
    expect(insert.body!.attendees).toEqual([{ email: guest.email, displayName: guest.name }]);
    expect(insert.body!.conferenceData.createRequest.conferenceSolutionKey.type).toBe("hangoutsMeet");
    expect(insert.body!.description).toContain("Pricing for a team of 12");
    expect(insert.body!.description).toContain(first.manage_url);
    const row = must(await admin.from("bookings").select("*").eq("id", first.id).single());
    expect(row).toMatchObject({
      status: "confirmed",
      provider_event_id: expect.stringMatching(/^event-/),
      summary_template: "oneOnOne",
      answers: [{ question: "What would you like to cover?", answer: "Pricing for a team of 12" }],
    });
    expect(row.manage_token_hash).toBe(hashToken(tokenOf(first.manage_url)));
  });

  it("refuses a missing required answer and a time that is already booked", async () => {
    await expect(createBooking(handle, "intro", { ...guest, start: iso(13), answers: {} })).rejects.toMatchObject({ status: 400 });
    await expect(
      createBooking(handle, "intro", { ...guest, email: "grace@example.invalid", start: iso(12) }),
    ).rejects.toMatchObject({ status: 409 });
  });

  it("never lets two live bookings overlap, even when the checks race", async () => {
    const row = must(await admin.from("bookings").select("*").eq("id", first.id).single());
    const { id: _id, created_at: _created, updated_at: _updated, ...copy } = row;
    const race = await admin.from("bookings").insert({
      ...copy,
      provider_event_id: null,
      starts_at: iso(12, 15),
      ends_at: iso(12, 45),
      manage_token_hash: hashToken(randomUUID()),
    });
    expect(race.error?.code).toBe("23P01");
  });

  it("keeps nothing when Google refuses the event", async () => {
    failInsert = true;
    await expect(createBooking(handle, "intro", { ...guest, start: iso(14) })).rejects.toMatchObject({ status: 502 });
    failInsert = false;
    expect(must(await admin.from("bookings").select("id").eq("user_id", userID).eq("starts_at", iso(14)))).toEqual([]);
  });

  it("shows a guest only their own booking, and only with its private link", async () => {
    const view = await guestView(first.id, tokenOf(first.manage_url));
    expect(view).toMatchObject({ status: "confirmed", host: "Integration Host", handle, slug: "intro", meeting_url: first.meeting_url });
    expect(view).not.toHaveProperty("guest_email");
    expect(view).not.toHaveProperty("answers");
    await expect(guestView(first.id, randomBytes(32).toString("base64url"))).rejects.toMatchObject({ status: 404 });
  });

  it("moves a booking only to a free time, and Google tells the guest", async () => {
    const token = tokenOf(first.manage_url);
    googleBusy = [{ start: iso(15), end: iso(16) }];
    await expect(rescheduleBooking(first.id, token, iso(15), "UTC")).rejects.toMatchObject({ status: 409 });
    googleBusy = [];
    const before = calls.length;
    expect(await rescheduleBooking(first.id, token, iso(15), "UTC")).toEqual({ starts_at: iso(15), ends_at: iso(15, 30) });
    const patch = calls.slice(before).find((c) => c.method === "PATCH")!;
    expect(patch.url.searchParams.get("sendUpdates")).toBe("all");
    expect(patch.body!.start.dateTime).toBe(iso(15));
    const slots = await open();
    expect(slots).toContain(iso(12));
    expect(slots).not.toContain(iso(15));
  });

  it("cancels from the guest's link or by the host, and frees the time", async () => {
    const before = calls.length;
    expect(await cancelBooking(first.id, { token: tokenOf(first.manage_url) }, "Something came up")).toEqual({ status: "cancelled" });
    const remove = calls.slice(before).find((c) => c.method === "DELETE")!;
    expect(remove.url.searchParams.get("sendUpdates")).toBe("all");
    expect(must(await admin.from("bookings").select("status,cancelled_by,cancel_reason").eq("id", first.id).single())).toEqual({
      status: "cancelled",
      cancelled_by: "guest",
      cancel_reason: "Something came up",
    });
    expect((await guestView(first.id, tokenOf(first.manage_url))).meeting_url).toBeNull();
    const again = await createBooking(handle, "intro", { ...guest, start: iso(15) });
    await expect(cancelBooking(again.id, { hostID: users[1] })).rejects.toMatchObject({ status: 404 });
    expect(await cancelBooking(again.id, { hostID: userID })).toEqual({ status: "cancelled" });
  });

  it("releases a time held by a booking that never finished", async () => {
    must(
      await admin.from("bookings").insert({
        user_id: userID,
        event_type_id: typeID,
        status: "pending",
        starts_at: iso(16),
        ends_at: iso(16, 30),
        title: "Intro call",
        summary_template: "oneOnOne",
        location_kind: "google_meet",
        guest_name: "Stalled guest",
        guest_email: "stalled@example.invalid",
        guest_time_zone: "UTC",
        manage_token_hash: hashToken(randomUUID()),
        created_at: new Date(Date.now() - 20 * 60_000).toISOString(),
      }),
    );
    expect(await open()).toContain(iso(16));
  });

  it("attaches the guest's booking details to the host's agenda", async () => {
    const booked = await createBooking(handle, "intro", { ...guest, start: iso(20) });
    const { provider_event_id } = must(await admin.from("bookings").select("provider_event_id").eq("id", booked.id).single());
    must(
      await admin.rpc("replace_calendar_events", {
        p_connection_id: connectionID,
        p_events: [
          {
            calendar_id: "primary",
            id: provider_event_id,
            ical_uid: `${provider_event_id}@google.com`,
            title: "Intro call: Integration Host and Ada Guest",
            starts_at: iso(20),
            ends_at: iso(20, 30),
            meeting_url: booked.meeting_url,
            attendees: [],
          },
        ],
      }),
    );
    const view = await agenda(host, 30);
    expect(view.bookingEnabled).toBe(true);
    expect(view.events.find((e) => e.id === provider_event_id)?.booking).toMatchObject({
      id: booked.id,
      event_type: "Intro call",
      template: "oneOnOne",
      guest_name: "Ada Guest",
      answers: [{ question: "What would you like to cover?", answer: "Pricing for a team of 12" }],
    });
  });

  it("suggests free time to connected AI apps without holding it", async () => {
    const count = async () => must(await admin.from("bookings").select("id").eq("user_id", userID)).length;
    const before = await count();
    const result = await freeTimes(userID, { days: 7, durationMinutes: 30, timeZone: "UTC" });
    const times = result.slots.map((d) => d.toISOString());
    expect(result.hours).toBe("your booking hours");
    expect(times).toContain(iso(9));
    for (const busy of [iso(18), iso(20)]) expect(times).not.toContain(busy);
    expect(await count()).toBe(before);
  });

  it("limits public requests per address without storing the address", async () => {
    const bucket = `it${Date.now()}`;
    const from = (address: string) => new Request(`${site}/api/book/${handle}/intro`, { headers: { "x-forwarded-for": address } });
    await rateLimit(from("203.0.113.7"), bucket, 2, 3600);
    await rateLimit(from("203.0.113.7"), bucket, 2, 3600);
    await expect(rateLimit(from("203.0.113.7"), bucket, 2, 3600)).rejects.toMatchObject({ status: 429 });
    await rateLimit(from("203.0.113.8"), bucket, 2, 3600);
    const stored = must(await admin.from("booking_rate_limits").select("bucket").like("bucket", `${bucket}:%`));
    expect(stored.length).toBe(2);
    expect(stored.some((r) => r.bucket.includes("203.0.113"))).toBe(false);
  });

  it("accepts bookings only from Voice Notes' own pages", async () => {
    const response = await book(
      new Request(`${site}/api/book/${handle}/intro`, {
        method: "POST",
        headers: { origin: "https://elsewhere.example", "content-type": "application/json", "x-forwarded-for": "203.0.113.9" },
        body: JSON.stringify({ ...guest, start: iso(21) }),
      }),
      { params: Promise.resolve({ handle, slug: "intro" }) },
    );
    expect(response.status).toBe(403);
  });
});
