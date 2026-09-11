import { effectiveProfile } from "./schedules";
import { bookingOperation } from "./operation";
import {
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";
import { accessToken, connectionsFor, derivedSecret } from "../calendar";
import { siteURL } from "../config";
import {
  busyFromEvents,
  canBook,
  canQueryFreeBusy,
  google,
  GoogleError,
  meetLink,
} from "../google";
import { HttpError } from "../http";
import { adminClient } from "../supabase/server";
import {
  availableSlots,
  isSlotAvailable,
  isTimeZone,
  type Interval,
  type SlotRules,
} from "./availability";
import type { EventType, Profile } from "./schema";

const DAY = 86_400_000;
const LOCATION_LABEL: Record<string, string> = {
  google_meet: "Google Meet",
  video_link: "Video call",
  in_person: "In person",
  phone: "Phone call",
};

export const rulesFor = (profile: Profile, type: EventType): SlotRules => ({
  timeZone: profile.time_zone,
  weeklyHours: profile.weekly_hours,
  dateOverrides: profile.date_overrides,
  durationMinutes: type.duration_minutes,
  slotIntervalMinutes: type.slot_interval_minutes,
  minimumNoticeMinutes: type.minimum_notice_minutes,
  bufferBeforeMinutes: type.buffer_before_minutes,
  bufferAfterMinutes: type.buffer_after_minutes,
  bookingWindowDays: type.booking_window_days,
  dailyLimit: type.daily_limit,
});

export const hashToken = (token: string) =>
  createHash("sha256").update(token).digest("hex");
function sameHash(token: string, hash: string) {
  const a = Buffer.from(hashToken(token), "hex"),
    b = Buffer.from(hash, "hex");
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Public pages are limited per hashed address; raw addresses are never stored. */
export async function rateLimit(
  request: Request,
  bucket: string,
  limit: number,
  windowSeconds: number,
) {
  const address =
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    request.headers.get("x-real-ip") ||
    "unknown";
  const id = createHmac("sha256", derivedSecret("booking-rate-limit"))
    .update(address)
    .digest("hex")
    .slice(0, 40);
  const { data, error } = await adminClient().rpc("hit_booking_rate_limit", {
    p_bucket: `${bucket}:${id}`,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error)
    throw new HttpError(
      503,
      "Booking is briefly unavailable. Try again shortly.",
    );
  if (!data)
    throw new HttpError(429, "Too many requests. Wait a minute and try again.");
}

/** Public requests must come from Voice Notes' own booking pages. */
export function sameOrigin(request: Request) {
  if (request.headers.get("origin") !== siteURL())
    throw new HttpError(403, "Book from the Voice Notes booking page.");
}

export async function publicEventType(handle: string, slug: string) {
  const db = adminClient();
  const { data: profile, error } = await db
    .from("booking_profiles")
    .select("*")
    .eq("handle", handle.toLowerCase())
    .maybeSingle();
  if (error) throw error;
  if (!profile) return null;
  const { data: type, error: typeError } = await db
    .from("event_types")
    .select("*")
    .eq("user_id", profile.user_id)
    .eq("slug", slug.toLowerCase())
    .eq("active", true)
    .maybeSingle();
  if (typeError) throw typeError;
  return type
    ? {
        profile: await effectiveProfile(profile as Profile, type as EventType),
        type: type as EventType,
      }
    : null;
}

export async function publicProfile(handle: string) {
  const db = adminClient();
  const { data: profile, error } = await db
    .from("booking_profiles")
    .select("user_id,handle,display_name,time_zone")
    .eq("handle", handle.toLowerCase())
    .maybeSingle();
  if (error) throw error;
  if (!profile) return null;
  const { data: types, error: typeError } = await db
    .from("event_types")
    .select("slug,title,description,duration_minutes,location_kind")
    .eq("user_id", profile.user_id)
    .eq("active", true)
    .order("position")
    .order("created_at");
  if (typeError) throw typeError;
  return { profile, types: types ?? [] };
}

/**
 * Everything that makes the host busy between two instants: every counted calendar on every
 * connected account, busy blocks shared from their Mac, and bookings not yet on a calendar.
 * A calendar that cannot be read fails the request rather than risk a double booking.
 */
export async function hostBusy(
  userID: string,
  from: Date,
  to: Date,
  excludeBooking?: string,
) {
  const db = adminClient();
  await db
    .from("bookings")
    .update({
      status: "cancelled",
      cancelled_by: "system",
      cancelled_at: new Date().toISOString(),
      cancel_reason: "Not completed",
    })
    .eq("user_id", userID)
    .eq("status", "pending")
    .lt("created_at", new Date(Date.now() - 10 * 60_000).toISOString());
  const busy: Interval[] = [];
  const [
    connections,
    { data: sources, error: sourceError },
    { data: device },
    { data: booked, error: bookedError },
  ] = await Promise.all([
    connectionsFor(userID),
    db
      .from("calendar_sources")
      .select("connection_id,calendar_id")
      .eq("user_id", userID)
      .eq("selected", true),
    db
      .from("device_busy_times")
      .select("blocks")
      .eq("user_id", userID)
      .maybeSingle(),
    db
      .from("bookings")
      .select("id,starts_at,ends_at")
      .eq("user_id", userID)
      .neq("status", "cancelled")
      .lt("starts_at", to.toISOString())
      .gt("ends_at", from.toISOString()),
  ]);
  if (sourceError) throw sourceError;
  if (bookedError) throw bookedError;
  for (const connection of connections) {
    const ids = (sources ?? [])
      .filter((s) => s.connection_id === connection.id)
      .map((s) => s.calendar_id as string);
    if (!ids.length) continue;
    try {
      const api = google(await accessToken(connection));
      if (canQueryFreeBusy(connection.scopes))
        busy.push(...(await api.busy(ids, from, to)));
      else
        for (const id of ids)
          busy.push(...busyFromEvents(await api.events(id, from, to)));
    } catch {
      throw new HttpError(
        503,
        "The host's calendar couldn't be checked just now. Try again shortly.",
      );
    }
  }
  for (const b of (device?.blocks ?? []) as { start: string; end: string }[]) {
    const block = { start: new Date(b.start), end: new Date(b.end) };
    if (block.start < to && block.end > from) busy.push(block);
  }
  for (const b of booked ?? [])
    if (b.id !== excludeBooking)
      busy.push({ start: new Date(b.starts_at), end: new Date(b.ends_at) });
  return busy;
}

async function startsOfType(
  typeID: string,
  around: Date,
  excludeBooking?: string,
) {
  const { data, error } = await adminClient()
    .from("bookings")
    .select("id,starts_at")
    .eq("event_type_id", typeID)
    .neq("status", "cancelled")
    .gte("starts_at", new Date(around.getTime() - 2 * DAY).toISOString())
    .lte("starts_at", new Date(around.getTime() + 2 * DAY).toISOString());
  if (error) throw error;
  return (data ?? [])
    .filter((b) => b.id !== excludeBooking)
    .map((b) => new Date(b.starts_at));
}

export async function slotsFor(
  handle: string,
  slug: string,
  from: Date,
  to: Date,
  inviteeTimeZone: string,
) {
  const found = await publicEventType(handle, slug);
  if (!found) throw new HttpError(404, "This booking link isn't available.");
  const { profile, type } = found;
  if (to.getTime() - from.getTime() > 42 * DAY || to <= from)
    throw new HttpError(400, "Choose up to six weeks at a time.");
  const busy = await hostBusy(profile.user_id, from, to);
  const { data: booked, error } = await adminClient()
    .from("bookings")
    .select("starts_at")
    .eq("event_type_id", type.id)
    .neq("status", "cancelled")
    .gte("starts_at", new Date(from.getTime() - DAY).toISOString())
    .lte("starts_at", new Date(to.getTime() + DAY).toISOString());
  if (error) throw error;
  return availableSlots(rulesFor(profile, type), {
    from,
    to,
    busy,
    inviteeTimeZone,
    bookedStartsOfType: (booked ?? []).map((b) => new Date(b.starts_at)),
  });
}

type Answer = { question: string; answer: string };
function answersFor(
  type: EventType,
  raw: Record<string, string>,
  phone?: string,
): Answer[] {
  const answers: Answer[] = [];
  if (type.location_kind === "phone") {
    if (!phone || !/^[+()\d\s.-]{6,40}$/.test(phone))
      throw new HttpError(400, "Add a phone number the host can call.");
    answers.push({ question: "Phone number", answer: phone });
  }
  for (const q of type.questions) {
    const value = (raw[q.id] ?? "").trim();
    if (q.required && !value) throw new HttpError(400, `Answer “${q.label}”.`);
    if (value) answers.push({ question: q.label, answer: value });
  }
  return answers;
}

function eventBody(
  booking: { id: string; starts_at: string; ends_at: string },
  profile: Profile,
  type: EventType,
  guest: { name: string; email: string },
  answers: Answer[],
  manageURL: string,
) {
  const phone = answers.find((a) => a.question === "Phone number")?.answer;
  const location =
    type.location_kind === "in_person" || type.location_kind === "video_link"
      ? type.location_detail
      : type.location_kind === "phone"
        ? `${profile.display_name} will call ${phone}`
        : undefined;
  const lines = [
    type.description,
    answers.length
      ? answers.map((a) => `${a.question}\n${a.answer}`).join("\n\n")
      : "",
    `Need to make a change? Reschedule or cancel: ${manageURL}`,
    "Booked with Voice Notes.",
  ].filter(Boolean);
  return {
    summary: `${type.title}: ${profile.display_name} and ${guest.name}`,
    description: lines.join("\n\n"),
    start: { dateTime: booking.starts_at, timeZone: profile.time_zone },
    end: { dateTime: booking.ends_at, timeZone: profile.time_zone },
    attendees: [{ email: guest.email, displayName: guest.name }],
    ...(location ? { location } : {}),
    ...(type.location_kind === "google_meet"
      ? {
          conferenceData: {
            createRequest: {
              requestId: booking.id,
              conferenceSolutionKey: { type: "hangoutsMeet" },
            },
          },
        }
      : {}),
    extendedProperties: { private: { voiceNotesBookingId: booking.id } },
  };
}

async function destination(profile: Profile) {
  if (!profile.destination_connection_id || !profile.destination_calendar_id)
    throw new HttpError(
      409,
      "This booking page isn't ready yet. The host needs to choose a calendar.",
    );
  const connection = (await connectionsFor(profile.user_id)).find(
    (c) => c.id === profile.destination_connection_id,
  );
  if (!connection || !canBook(connection.scopes))
    throw new HttpError(
      409,
      "This booking page isn't ready yet. The host needs to reconnect their calendar.",
    );
  return { connection, calendarID: profile.destination_calendar_id };
}

export async function createBooking(
  handle: string,
  slug: string,
  input: {
    start: string;
    name: string;
    email: string;
    time_zone: string;
    phone?: string;
    answers: Record<string, string>;
  },
) {
  const found = await publicEventType(handle, slug);
  if (!found) throw new HttpError(404, "This booking link isn't available.");
  const { profile, type } = found;
  const target = await destination(profile);
  const answers = answersFor(type, input.answers, input.phone);
  const start = new Date(input.start),
    end = new Date(start.getTime() + type.duration_minutes * 60_000);
  const busy = await hostBusy(
    profile.user_id,
    new Date(start.getTime() - DAY),
    new Date(end.getTime() + DAY),
  );
  if (
    !isSlotAvailable(rulesFor(profile, type), start, {
      busy,
      inviteeTimeZone: input.time_zone,
      bookedStartsOfType: await startsOfType(type.id, start),
    })
  )
    throw new HttpError(
      409,
      "That time was just taken or is no longer available. Choose another time.",
    );
  const token = randomBytes(32).toString("base64url");
  const db = adminClient();
  const { data: booking, error } = await db
    .from("bookings")
    .insert({
      user_id: profile.user_id,
      event_type_id: type.id,
      status: "pending",
      starts_at: start.toISOString(),
      ends_at: end.toISOString(),
      title: type.title,
      summary_template: type.summary_template,
      location_kind: type.location_kind,
      location_detail: type.location_detail,
      guest_name: input.name,
      guest_email: input.email,
      guest_time_zone: input.time_zone,
      answers,
      connection_id: target.connection.id,
      calendar_id: target.calendarID,
      manage_token_hash: hashToken(token),
    })
    .select("id,starts_at,ends_at")
    .single();
  if (error?.code === "23P01")
    throw new HttpError(409, "That time was just taken. Choose another time.");
  if (error) throw error;
  const manageURL = `${siteURL()}/book/manage/${booking.id}#${token}`;
  let event;
  try {
    const api = google(await accessToken(target.connection));
    event = await api.insertEvent(
      target.calendarID,
      eventBody(
        {
          id: booking.id,
          starts_at: start.toISOString(),
          ends_at: end.toISOString(),
        },
        profile,
        type,
        input,
        answers,
        manageURL,
      ),
    );
  } catch (cause) {
    await db.from("bookings").delete().eq("id", booking.id);
    throw new HttpError(
      502,
      cause instanceof GoogleError &&
      (cause.status === 401 || cause.status === 403)
        ? "The host's calendar needs to be reconnected. Nothing was booked."
        : "Your booking couldn't be added to the calendar. Nothing was booked. Try again.",
    );
  }
  const meeting =
    meetLink(event) ||
    (type.location_kind === "video_link" ? type.location_detail : null);
  const { error: confirm } = await db
    .from("bookings")
    .update({
      status: "confirmed",
      provider_event_id: event.id,
      meeting_url: meeting,
      updated_at: new Date().toISOString(),
    })
    .eq("id", booking.id);
  if (confirm) throw confirm;
  return {
    id: booking.id as string,
    starts_at: start.toISOString(),
    ends_at: end.toISOString(),
    meeting_url: meeting,
    location: LOCATION_LABEL[type.location_kind],
    manage_url: manageURL,
  };
}

async function bookingByToken(id: string, token: string) {
  if (!/^[0-9a-f-]{36}$/.test(id) || token.length < 20 || token.length > 100)
    throw new HttpError(404, "This booking link isn't valid.");
  const { data, error } = await adminClient()
    .from("bookings")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  if (!data || !sameHash(token, data.manage_token_hash))
    throw new HttpError(404, "This booking link isn't valid.");
  return data;
}

/** What a guest may see about their own booking. */
export async function guestView(id: string, token: string) {
  const b = await bookingByToken(id, token);
  const db = adminClient();
  const [{ data: profile }, { data: type }] = await Promise.all([
    db
      .from("booking_profiles")
      .select("handle,display_name,time_zone")
      .eq("user_id", b.user_id)
      .maybeSingle(),
    b.event_type_id
      ? db
          .from("event_types")
          .select("slug,active,duration_minutes")
          .eq("id", b.event_type_id)
          .maybeSingle()
      : Promise.resolve({ data: null }),
  ]);
  return {
    id: b.id,
    status: b.status,
    title: b.title,
    host: profile?.display_name ?? "Your host",
    handle: profile?.handle ?? null,
    slug: type?.active ? type.slug : null,
    starts_at: b.starts_at,
    ends_at: b.ends_at,
    location: LOCATION_LABEL[b.location_kind] ?? b.location_kind,
    meeting_url: b.status === "confirmed" ? b.meeting_url : null,
    guest_name: b.guest_name,
    guest_time_zone: b.guest_time_zone,
  };
}

async function removeFromCalendar(b: {
  user_id: string;
  connection_id: string | null;
  calendar_id: string | null;
  provider_event_id: string | null;
}) {
  if (!b.connection_id || !b.calendar_id || !b.provider_event_id) return;
  const connection = (await connectionsFor(b.user_id)).find(
    (c) => c.id === b.connection_id,
  );
  if (!connection) return;
  await google(await accessToken(connection)).deleteEvent(
    b.calendar_id,
    b.provider_event_id,
  );
}

async function cancelBookingUnlocked(
  id: string,
  by: { token: string } | { hostID: string },
  reason?: string,
) {
  const b =
    "token" in by
      ? await bookingByToken(id, by.token)
      : (
          await adminClient()
            .from("bookings")
            .select("*")
            .eq("id", id)
            .eq("user_id", by.hostID)
            .maybeSingle()
        ).data;
  if (!b) throw new HttpError(404, "This booking isn't in your calendar.");
  if (b.status === "cancelled") return { status: "cancelled" };
  if (new Date(b.ends_at) < new Date())
    throw new HttpError(409, "This meeting has already happened.");
  try {
    await removeFromCalendar(b);
  } catch {
    throw new HttpError(
      502,
      "The calendar couldn't be updated. The booking is unchanged. Try again.",
    );
  }
  const { error } = await adminClient()
    .from("bookings")
    .update({
      status: "cancelled",
      cancelled_by: "token" in by ? "guest" : "host",
      cancelled_at: new Date().toISOString(),
      cancel_reason: reason?.slice(0, 1000) || null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", b.id);
  if (error) throw error;
  return { status: "cancelled" };
}

async function rescheduleBookingUnlocked(
  id: string,
  by: string | { hostID: string },
  startValue: string,
  inviteeTimeZone: string,
) {
  const b =
    typeof by === "string"
      ? await bookingByToken(id, by)
      : (
          await adminClient()
            .from("bookings")
            .select("*")
            .eq("id", id)
            .eq("user_id", by.hostID)
            .maybeSingle()
        ).data;
  if (!b) throw new HttpError(404, "Booking not found.");
  if (b.status !== "confirmed")
    throw new HttpError(409, "Only a confirmed booking can be moved.");
  if (new Date(b.starts_at) < new Date())
    throw new HttpError(409, "This meeting has already started.");
  const db = adminClient();
  const [{ data: baseProfile }, { data: type }] = await Promise.all([
    db
      .from("booking_profiles")
      .select("*")
      .eq("user_id", b.user_id)
      .maybeSingle(),
    b.event_type_id
      ? db
          .from("event_types")
          .select("*")
          .eq("id", b.event_type_id)
          .maybeSingle()
      : Promise.resolve({ data: null }),
  ]);
  if (!baseProfile || !type)
    throw new HttpError(
      409,
      "This meeting type is no longer offered. Cancel and book again.",
    );
  const profile = await effectiveProfile(
    baseProfile as Profile,
    type as EventType,
  );
  const start = new Date(startValue),
    end = new Date(start.getTime() + type.duration_minutes * 60_000);
  const busy = await hostBusy(
    b.user_id,
    new Date(start.getTime() - DAY),
    new Date(end.getTime() + DAY),
    b.id,
  );
  if (
    !isSlotAvailable(rulesFor(profile as Profile, type as EventType), start, {
      busy,
      inviteeTimeZone,
      bookedStartsOfType: await startsOfType(type.id, start, b.id),
    })
  )
    throw new HttpError(
      409,
      "That time is no longer available. Choose another time.",
    );
  const previous = { starts_at: b.starts_at, ends_at: b.ends_at };
  const { error } = await db
    .from("bookings")
    .update({
      starts_at: start.toISOString(),
      ends_at: end.toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", b.id);
  if (error?.code === "23P01")
    throw new HttpError(409, "That time was just taken. Choose another time.");
  if (error) throw error;
  try {
    const connection = (await connectionsFor(b.user_id)).find(
      (c) => c.id === b.connection_id,
    );
    if (!connection || !b.calendar_id || !b.provider_event_id)
      throw new Error("Missing calendar event");
    await google(await accessToken(connection)).patchEvent(
      b.calendar_id,
      b.provider_event_id,
      {
        start: { dateTime: start.toISOString(), timeZone: profile.time_zone },
        end: { dateTime: end.toISOString(), timeZone: profile.time_zone },
      },
    );
  } catch {
    await db.from("bookings").update(previous).eq("id", b.id);
    throw new HttpError(
      502,
      "The calendar couldn't be updated. Your original time is unchanged.",
    );
  }
  return { starts_at: start.toISOString(), ends_at: end.toISOString() };
}

/** Open times in the person's own hours, for their AI apps to suggest. Nothing is held. */
export async function freeTimes(
  userID: string,
  options: { days: number; durationMinutes: number; timeZone?: string },
) {
  const { data: profile, error } = await adminClient()
    .from("booking_profiles")
    .select("time_zone,weekly_hours,date_overrides")
    .eq("user_id", userID)
    .maybeSingle();
  if (error) throw error;
  const asked =
    options.timeZone && isTimeZone(options.timeZone) ? options.timeZone : null;
  const hostZone = profile?.time_zone ?? asked ?? "UTC";
  const zone = asked ?? hostZone;
  const now = new Date(),
    to = new Date(now.getTime() + options.days * DAY);
  const rules: SlotRules = {
    timeZone: hostZone,
    weeklyHours: profile?.weekly_hours ?? [
      { days: [1, 2, 3, 4, 5], start: "09:00", end: "17:00" },
    ],
    dateOverrides: profile?.date_overrides ?? [],
    durationMinutes: options.durationMinutes,
    slotIntervalMinutes: Math.min(options.durationMinutes, 30),
    minimumNoticeMinutes: 60,
    bufferBeforeMinutes: 0,
    bufferAfterMinutes: 0,
    bookingWindowDays: options.days + 1,
    dailyLimit: null,
  };
  const busy = await hostBusy(userID, now, to);
  return {
    timeZone: zone,
    hours: profile ? "your booking hours" : "weekdays 9:00–17:00",
    slots: availableSlots(rules, {
      from: now,
      to,
      busy,
      inviteeTimeZone: zone,
      now,
    }),
  };
}

export async function cancelBooking(
  id: string,
  by: { token: string } | { hostID: string },
  reason?: string,
) {
  return bookingOperation(id, () => cancelBookingUnlocked(id, by, reason));
}
export async function rescheduleBooking(
  id: string,
  by: string | { hostID: string },
  start: string,
  timeZone: string,
) {
  return bookingOperation(id, () =>
    rescheduleBookingUnlocked(id, by, start, timeZone),
  );
}
