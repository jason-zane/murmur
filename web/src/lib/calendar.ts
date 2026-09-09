import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { adminClient } from "./supabase/server";
import { meetingURL, type CalendarMeeting } from "./documents";
function key() {
  const bytes = Buffer.from(
    process.env.GOOGLE_TOKEN_ENCRYPTION_KEY || "",
    "base64",
  );
  if (bytes.length !== 32)
    throw new Error("Calendar encryption is not configured.");
  return bytes;
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
type GoogleEvent = {
  id: string;
  summary?: string;
  status?: string;
  start?: { dateTime?: string; date?: string };
  end?: { dateTime?: string; date?: string };
  hangoutLink?: string;
  conferenceData?: { entryPoints?: { entryPointType: string; uri?: string }[] };
  attendees?: {
    displayName?: string;
    email?: string;
    self?: boolean;
    responseStatus?: string;
  }[];
};
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
export async function refreshCalendar(userID: string, force = false) {
  const db = adminClient();
  const { data: connection, error: statusError } = await db
    .from("calendar_connections")
    .select("updated_at")
    .eq("user_id", userID)
    .maybeSingle();
  if (statusError) throw statusError;
  if (!connection) return;
  if (
    !force &&
    connection.updated_at &&
    Date.now() - Date.parse(connection.updated_at) < 300000
  )
    return;
  const { data: credentials, error } = await db
    .from("calendar_credentials")
    .select("encrypted_refresh_token")
    .eq("user_id", userID)
    .maybeSingle();
  if (error) throw error;
  if (!credentials) return;
  try {
    const token = await googleToken({
      grant_type: "refresh_token",
      refresh_token: decryptToken(credentials.encrypted_refresh_token),
    });
    const now = new Date(),
      until = new Date(now.getTime() + 30 * 86400000);
    let pageToken: string | undefined;
    const events: CalendarMeeting[] = [];
    for (let page = 0; page < 10; page++) {
      const q = new URLSearchParams({
        timeMin: now.toISOString(),
        timeMax: until.toISOString(),
        singleEvents: "true",
        orderBy: "startTime",
        maxResults: "250",
      });
      if (pageToken) q.set("pageToken", pageToken);
      const r = await fetch(
        `https://www.googleapis.com/calendar/v3/calendars/primary/events?${q}`,
        {
          headers: { Authorization: `Bearer ${token.access_token}` },
          signal: AbortSignal.timeout(15000),
        },
      );
      const body = await r.json();
      if (!r.ok)
        throw new Error(
          "Google Calendar could not be read. Check the connection and try again.",
        );
      events.push(
        ...((body.items as GoogleEvent[]) || [])
          .map(normalizeEvent)
          .filter((e): e is CalendarMeeting => Boolean(e)),
      );
      pageToken = body.nextPageToken;
      if (!pageToken) break;
    }
    if (pageToken)
      throw new Error(
        "There are too many events to refresh at once. Your previously synced agenda has been kept.",
      );
    // Replace the complete fetched window in one database transaction; no delete/upload gap.
    const { error: saveError } = await db.rpc("replace_calendar_events", {
      p_user_id: userID,
      p_events: events,
    });
    if (saveError) throw saveError;
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Calendar sync failed.";
    await db
      .from("calendar_connections")
      .update({ error: message })
      .eq("user_id", userID);
    throw error;
  }
}
