import {
  createCipheriv,
  createDecipheriv,
  hkdfSync,
  randomBytes,
} from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import { adminClient } from "./supabase/server";
import { meetingURL, type CalendarMeeting } from "./documents";
import {
  canListCalendars,
  GoogleError,
  google,
  type GoogleCalendar,
  type GoogleEvent,
} from "./google";
function key() {
  const bytes = Buffer.from(
    process.env.GOOGLE_TOKEN_ENCRYPTION_KEY || "",
    "base64",
  );
  if (bytes.length !== 32)
    throw new Error("Calendar encryption is not configured.");
  return bytes;
}
/** A separate key for each purpose, derived from the server's calendar encryption key. */
export function derivedSecret(label: string) {
  return Buffer.from(
    hkdfSync("sha256", key(), Buffer.alloc(0), `voice-notes:${label}`, 32),
  );
}
export function encryptToken(token: string) {
  const iv = randomBytes(12),
    cipher = createCipheriv("aes-256-gcm", key(), iv);
  const ciphertext = Buffer.concat([
    cipher.update(token, "utf8"),
    cipher.final(),
  ]);
  return [iv, cipher.getAuthTag(), ciphertext]
    .map((b) => b.toString("base64url"))
    .join(".");
}
export function decryptToken(value: string) {
  const [iv, tag, text] = value
    .split(".")
    .map((s) => Buffer.from(s, "base64url"));
  const decipher = createDecipheriv("aes-256-gcm", key(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(text), decipher.final()]).toString(
    "utf8",
  );
}
export async function googleToken(params: Record<string, string>) {
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    body: new URLSearchParams({
      ...params,
      client_id: process.env.GOOGLE_CLIENT_ID!,
      client_secret: process.env.GOOGLE_CLIENT_SECRET!,
    }),
    signal: AbortSignal.timeout(15000),
  });
  const body = await r.json();
  if (!r.ok || !body.access_token)
    throw new Error(
      "Google authorization expired. Reconnect Google Calendar in Connections.",
    );
  return body as {
    access_token: string;
    refresh_token?: string;
    scope?: string;
  };
}
export function normalizeEvent(e: GoogleEvent): CalendarMeeting | null {
  if (
    e.status === "cancelled" ||
    e.attendees?.some((a) => a.self && a.responseStatus === "declined")
  )
    return null;
  const start = e.start?.dateTime,
    end = e.end?.dateTime;
  if (
    !start ||
    !end ||
    !Number.isFinite(Date.parse(start)) ||
    !Number.isFinite(Date.parse(end))
  )
    return null;
  return {
    id: e.id,
    title: e.summary || "Untitled meeting",
    starts_at: start,
    ends_at: end,
    meeting_url: meetingURL(
      e.hangoutLink ||
        e.conferenceData?.entryPoints?.find((p) => p.entryPointType === "video")
          ?.uri,
    ),
    attendees: (e.attendees || []).map((a) => ({
      name: a.displayName || a.email || "Guest",
      ...(a.email ? { email: a.email } : {}),
    })),
  };
}

export type CalendarConnection = {
  id: string;
  user_id: string;
  email: string | null;
  scopes: string[];
  updated_at: string | null;
  error: string | null;
  created_at: string;
};
export type CalendarSource = {
  connection_id: string;
  user_id: string;
  calendar_id: string;
  name: string;
  time_zone: string | null;
  color: string | null;
  is_primary: boolean;
  can_write: boolean;
  selected: boolean;
};

/** Stores or refreshes one account. The same address reconnecting updates its existing row. */
export async function saveConnection(
  userID: string,
  email: string | null,
  scopes: string[],
  refreshToken: string,
) {
  const db = adminClient();
  const { data: existing, error } = await db
    .from("calendar_connections")
    .select("id,email")
    .eq("user_id", userID)
    .eq("provider", "google");
  if (error) throw error;
  const match = existing?.find(
    (c) => (c.email || "").toLowerCase() === (email || "").toLowerCase(),
  );
  let id = match?.id as string | undefined;
  if (id) {
    const { error: update } = await db
      .from("calendar_connections")
      .update({ email, scopes, error: null, updated_at: null })
      .eq("id", id);
    if (update) throw update;
  } else {
    const { data, error: insert } = await db
      .from("calendar_connections")
      .insert({
        user_id: userID,
        provider: "google",
        email,
        scopes,
        updated_at: null,
      })
      .select("id")
      .single();
    if (insert) throw insert;
    id = data.id as string;
  }
  const { error: credentials } = await db.from("calendar_credentials").upsert({
    connection_id: id,
    user_id: userID,
    encrypted_refresh_token: encryptToken(refreshToken),
    updated_at: new Date().toISOString(),
  });
  if (credentials) throw credentials;
  return id!;
}

/** A fresh access token for one account. Google reports its current grants each time. */
export async function accessToken(
  connection: Pick<CalendarConnection, "id" | "scopes">,
) {
  const db = adminClient();
  const { data, error } = await db
    .from("calendar_credentials")
    .select("encrypted_refresh_token")
    .eq("connection_id", connection.id)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("Reconnect this Google account in Connections.");
  const token = await googleToken({
    grant_type: "refresh_token",
    refresh_token: decryptToken(data.encrypted_refresh_token),
  });
  const granted = token.scope?.split(" ").filter(Boolean);
  if (
    granted?.length &&
    granted.sort().join(" ") !== [...connection.scopes].sort().join(" ")
  ) {
    await db
      .from("calendar_connections")
      .update({ scopes: granted })
      .eq("id", connection.id);
    connection.scopes = granted;
  }
  return token.access_token;
}

const writable = (c: GoogleCalendar) =>
  c.accessRole === "owner" || c.accessRole === "writer";

/** Mirrors the account's calendar list, keeping each calendar's selection. */
async function syncSources(
  connection: CalendarConnection,
  calendars: GoogleCalendar[],
) {
  const db = adminClient();
  const { data: existing, error } = await db
    .from("calendar_sources")
    .select("calendar_id,selected")
    .eq("connection_id", connection.id);
  if (error) throw error;
  const previous = new Map(
    (existing ?? []).map((s) => [
      s.calendar_id as string,
      s.selected as boolean,
    ]),
  );
  const rows: CalendarSource[] = calendars.slice(0, 200).map((c) => ({
    connection_id: connection.id,
    user_id: connection.user_id,
    calendar_id: c.id,
    name: (c.summaryOverride || c.summary || c.id).slice(0, 500),
    time_zone: c.timeZone ?? null,
    color: c.backgroundColor ?? null,
    is_primary: Boolean(c.primary),
    can_write: writable(c),
    selected: previous.get(c.id) ?? Boolean(c.primary),
  }));
  if (rows.length) {
    const { error: upsert } = await db
      .from("calendar_sources")
      .upsert(
        rows.map((r) => ({ ...r, updated_at: new Date().toISOString() })),
      );
    if (upsert) throw upsert;
  }
  const gone = [...previous.keys()].filter(
    (id) => !rows.some((r) => r.calendar_id === id),
  );
  if (gone.length) {
    const { error: remove } = await db
      .from("calendar_sources")
      .delete()
      .eq("connection_id", connection.id)
      .in("calendar_id", gone);
    if (remove) throw remove;
  }
  return rows;
}

/** Reads the account's calendar list and the next 30 days of its selected calendars. */
export async function refreshConnection(connection: CalendarConnection) {
  const token = await accessToken(connection);
  const api = google(token);
  const sources = canListCalendars(connection.scopes)
    ? await syncSources(connection, await api.calendars())
    : await syncSources(connection, [
        {
          id: "primary",
          summary: connection.email || "Primary calendar",
          primary: true,
          accessRole: "owner",
        },
      ]);
  const now = new Date(),
    until = new Date(now.getTime() + 90 * 86400000);
  const events: (CalendarMeeting & {
    calendar_id: string;
    ical_uid: string | null;
  })[] = [];
  for (const source of sources.filter((s) => s.selected).slice(0, 25)) {
    let items: GoogleEvent[];
    try {
      items = await api.events(
        source.calendar_id,
        new Date(now.getTime() - 90 * 86400000),
        until,
      );
    } catch (error) {
      if (error instanceof GoogleError && error.status === 413)
        throw new Error(
          `“${source.name}” has too many events to refresh at once. Your previously synced agenda has been kept.`,
        );
      throw error;
    }
    for (const item of items) {
      const event = normalizeEvent(item);
      if (event)
        events.push({
          ...event,
          calendar_id: source.calendar_id,
          ical_uid: item.iCalUID ?? null,
        });
    }
  }
  const { error } = await adminClient().rpc("replace_calendar_events", {
    p_connection_id: connection.id,
    p_events: events,
  });
  if (error) throw error;
}

export async function connectionsFor(userID: string) {
  const { data, error } = await adminClient()
    .from("calendar_connections")
    .select("id,user_id,email,scopes,updated_at,error,created_at")
    .eq("user_id", userID)
    .order("created_at");
  if (error) throw error;
  return (data ?? []) as CalendarConnection[];
}

/**
 * Refreshes each account that is due. One account failing records its own error and never
 * blocks the others; the call fails only when every account it tried failed.
 */
export async function refreshCalendar(userID: string, force = false) {
  const connections = await connectionsFor(userID);
  const due = connections.filter(
    (c) =>
      force || !c.updated_at || Date.now() - Date.parse(c.updated_at) >= 300000,
  );
  let firstError: unknown = null,
    failures = 0;
  for (const connection of due) {
    try {
      await refreshConnection(connection);
    } catch (error) {
      failures++;
      firstError ??= error;
      const message =
        error instanceof Error ? error.message : "Calendar sync failed.";
      await adminClient()
        .from("calendar_connections")
        .update({ error: message })
        .eq("id", connection.id);
    }
  }
  if (due.length && failures === due.length) throw firstError;
}

export type AgendaEvent = CalendarMeeting;

/** The merged agenda, readable with the person's own client so row security applies. */
export async function agenda(
  client: SupabaseClient,
  days = 30,
  history = false,
) {
  const now = new Date();
  const [events, connections, sources, profile] = await Promise.all([
    client
      .from("calendar_events")
      .select(
        "id,ical_uid,connection_id,calendar_id,title,starts_at,ends_at,meeting_url,attendees",
      )
      .gt(
        "ends_at",
        new Date(now.getTime() - (history ? 90 : 0) * 86400000).toISOString(),
      )
      .lt("starts_at", new Date(now.getTime() + days * 86400000).toISOString())
      .order("starts_at")
      .limit(750),
    client
      .from("calendar_connections")
      .select("id,email,scopes,updated_at,error,created_at")
      .order("created_at"),
    client
      .from("calendar_sources")
      .select(
        "connection_id,calendar_id,name,color,is_primary,can_write,selected",
      )
      .order("is_primary", { ascending: false })
      .order("name"),
    client.from("booking_profiles").select("handle").maybeSingle(),
  ]);
  if (events.error) throw events.error;
  if (connections.error) throw connections.error;
  const seen = new Set<string>();
  const unique = (events.data ?? []).filter((e) => {
    const key = e.ical_uid ? `${e.ical_uid}@${e.starts_at}` : e.id;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  const ids = unique.map((e) => e.id);
  const bookings = ids.length
    ? await client
        .from("bookings")
        .select(
          "id,provider_event_id,title,summary_template,guest_name,guest_email,answers,event_types(title)",
        )
        .eq("status", "confirmed")
        .in("provider_event_id", ids.slice(0, 500))
    : { data: [], error: null };
  const byEvent = new Map(
    (bookings.data ?? []).map((b) => [b.provider_event_id as string, b]),
  );
  const list: AgendaEvent[] = unique
    .slice(0, history ? 750 : 250)
    .map(({ ical_uid: _, ...e }) => {
      const b = byEvent.get(e.id);
      return b
        ? {
            ...e,
            booking: {
              id: b.id,
              event_type:
                (b.event_types as unknown as { title?: string } | null)
                  ?.title || b.title,
              template: b.summary_template,
              guest_name: b.guest_name,
              guest_email: b.guest_email,
              answers: b.answers as { question: string; answer: string }[],
            },
          }
        : e;
    });
  const all = connections.data ?? [];
  return {
    events: list,
    connections: all,
    calendars: sources.data ?? [],
    bookingEnabled: Boolean(profile.data),
    // Earlier Mac builds read a single connection.
    connection: all.length
      ? {
          email: all[0].email,
          updated_at:
            all
              .map((c) => c.updated_at)
              .filter(Boolean)
              .sort()[0] ?? null,
          error: all.find((c) => c.error)?.error ?? null,
        }
      : null,
  };
}

/** Revokes and removes one account, or every account when none is named. */
export async function disconnect(userID: string, connectionID?: string) {
  const db = adminClient();
  let query = db
    .from("calendar_credentials")
    .select("connection_id,encrypted_refresh_token")
    .eq("user_id", userID);
  if (connectionID) query = query.eq("connection_id", connectionID);
  const { data: credentials, error } = await query;
  if (error) throw error;
  for (const c of credentials ?? []) {
    try {
      await fetch("https://oauth2.googleapis.com/revoke", {
        method: "POST",
        body: new URLSearchParams({
          token: decryptToken(c.encrypted_refresh_token),
        }),
        signal: AbortSignal.timeout(10000),
      });
    } catch {}
  }
  let remove = db.from("calendar_connections").delete().eq("user_id", userID);
  if (connectionID) remove = remove.eq("id", connectionID);
  const { error: removeError } = await remove;
  if (removeError) throw removeError;
}
