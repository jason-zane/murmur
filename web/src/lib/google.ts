// Google Calendar calls made with the host's own account. Invitations are sent by Google
// from the host's calendar; Voice Notes never sends email itself.
const API = "https://www.googleapis.com/calendar/v3";

export const SCOPE = {
  eventsRead: "https://www.googleapis.com/auth/calendar.events.readonly",
  events: "https://www.googleapis.com/auth/calendar.events",
  calendarList: "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
  freeBusy: "https://www.googleapis.com/auth/calendar.freebusy",
  legacyRead: "https://www.googleapis.com/auth/calendar.readonly",
} as const;
/** Connecting an account only asks to read. Booking asks for more when it is turned on. */
export const READ_SCOPES = ["openid", "email", SCOPE.eventsRead, SCOPE.calendarList];
export const BOOKING_SCOPES = [...READ_SCOPES, SCOPE.events, SCOPE.freeBusy];

const has = (scopes: readonly string[], scope: string) => scopes.includes(scope);
export const canReadEvents = (s: readonly string[]) =>
  has(s, SCOPE.eventsRead) || has(s, SCOPE.events) || has(s, SCOPE.legacyRead);
export const canListCalendars = (s: readonly string[]) =>
  has(s, SCOPE.calendarList) || has(s, SCOPE.legacyRead);
export const canQueryFreeBusy = (s: readonly string[]) =>
  has(s, SCOPE.freeBusy) || has(s, SCOPE.legacyRead);
export const canBook = (s: readonly string[]) => has(s, SCOPE.events) && canQueryFreeBusy(s);

export class GoogleError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

export type GoogleCalendar = {
  id: string;
  summary?: string;
  summaryOverride?: string;
  primary?: boolean;
  accessRole?: "freeBusyReader" | "reader" | "writer" | "owner";
  timeZone?: string;
  backgroundColor?: string;
  deleted?: boolean;
  hidden?: boolean;
};
export type GoogleEvent = {
  id: string;
  iCalUID?: string;
  summary?: string;
  status?: string;
  transparency?: string;
  start?: { dateTime?: string; date?: string };
  end?: { dateTime?: string; date?: string };
  hangoutLink?: string;
  htmlLink?: string;
  conferenceData?: { entryPoints?: { entryPointType: string; uri?: string }[] };
  attendees?: { displayName?: string; email?: string; self?: boolean; responseStatus?: string }[];
};

export function google(accessToken: string) {
  async function call<T>(path: string, init: RequestInit = {}, allowMissing = false): Promise<T | null> {
    const response = await fetch(`${API}${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        ...(init.body ? { "Content-Type": "application/json" } : {}),
      },
      signal: AbortSignal.timeout(15000),
    });
    if (allowMissing && (response.status === 404 || response.status === 410)) return null;
    if (!response.ok) {
      const status = response.status;
      throw new GoogleError(
        status,
        status === 401 || status === 403
          ? "Google Calendar access was revoked or is missing a permission. Reconnect this account in Connections."
          : "Google Calendar did not respond. Try again shortly.",
      );
    }
    return response.status === 204 ? null : ((await response.json()) as T);
  }
  const q = (params: Record<string, string>) => new URLSearchParams(params).toString();
  return {
    async calendars(): Promise<GoogleCalendar[]> {
      const items: GoogleCalendar[] = [];
      let pageToken: string | undefined;
      for (let page = 0; page < 10; page++) {
        const body = await call<{ items?: GoogleCalendar[]; nextPageToken?: string }>(
          `/users/me/calendarList?${q({ maxResults: "250", ...(pageToken ? { pageToken } : {}) })}`,
        );
        items.push(...(body?.items ?? []));
        pageToken = body?.nextPageToken;
        if (!pageToken) break;
      }
      return items.filter((c) => !c.deleted);
    },
    async events(calendarId: string, timeMin: Date, timeMax: Date): Promise<GoogleEvent[]> {
      const items: GoogleEvent[] = [];
      let pageToken: string | undefined;
      for (let page = 0; page < 10; page++) {
        const body = await call<{ items?: GoogleEvent[]; nextPageToken?: string }>(
          `/calendars/${encodeURIComponent(calendarId)}/events?${q({
            timeMin: timeMin.toISOString(),
            timeMax: timeMax.toISOString(),
            singleEvents: "true",
            orderBy: "startTime",
            maxResults: "250",
            ...(pageToken ? { pageToken } : {}),
          })}`,
        );
        items.push(...(body?.items ?? []));
        pageToken = body?.nextPageToken;
        if (!pageToken) return items;
      }
      throw new GoogleError(413, "There are too many events to read at once.");
    },
    /** Google limits one query to 90 days and 50 calendars. */
    async busy(calendarIds: string[], timeMin: Date, timeMax: Date) {
      const result: { start: Date; end: Date }[] = [];
      for (let i = 0; i < calendarIds.length; i += 50) {
        for (let from = timeMin.getTime(); from < timeMax.getTime(); from += 89 * 86_400_000) {
          const until = Math.min(timeMax.getTime(), from + 89 * 86_400_000);
          const body = await call<{
            calendars?: Record<string, { busy?: { start: string; end: string }[]; errors?: unknown[] }>;
          }>(`/freeBusy`, {
            method: "POST",
            body: JSON.stringify({
              timeMin: new Date(from).toISOString(),
              timeMax: new Date(until).toISOString(),
              items: calendarIds.slice(i, i + 50).map((id) => ({ id })),
            }),
          });
          for (const [id, calendar] of Object.entries(body?.calendars ?? {})) {
            if (calendar.errors?.length)
              throw new GoogleError(502, `Busy times for ${id} could not be read.`);
            for (const b of calendar.busy ?? []) result.push({ start: new Date(b.start), end: new Date(b.end) });
          }
        }
      }
      return result;
    },
    insertEvent(calendarId: string, event: Record<string, unknown>) {
      return call<GoogleEvent>(
        `/calendars/${encodeURIComponent(calendarId)}/events?${q({ sendUpdates: "all", conferenceDataVersion: "1" })}`,
        { method: "POST", body: JSON.stringify(event) },
      ) as Promise<GoogleEvent>;
    },
    patchEvent(calendarId: string, eventId: string, patch: Record<string, unknown>) {
      return call<GoogleEvent>(
        `/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}?${q({ sendUpdates: "all", conferenceDataVersion: "1" })}`,
        { method: "PATCH", body: JSON.stringify(patch) },
      ) as Promise<GoogleEvent>;
    },
    /** A missing event counts as already removed. */
    async deleteEvent(calendarId: string, eventId: string) {
      await call(
        `/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}?${q({ sendUpdates: "all" })}`,
        { method: "DELETE" },
        true,
      );
    },
  };
}

/** Busy times from event listings, for accounts that only granted read access. */
export function busyFromEvents(events: GoogleEvent[]) {
  return events
    .filter(
      (e) =>
        e.status !== "cancelled" &&
        e.transparency !== "transparent" &&
        !e.attendees?.some((a) => a.self && a.responseStatus === "declined"),
    )
    .map((e) => ({
      start: new Date(e.start?.dateTime ?? `${e.start?.date}T00:00:00Z`),
      end: new Date(e.end?.dateTime ?? `${e.end?.date}T00:00:00Z`),
    }))
    .filter((b) => Number.isFinite(b.start.getTime()) && Number.isFinite(b.end.getTime()) && b.end > b.start);
}

export function meetLink(event: GoogleEvent) {
  return (
    event.hangoutLink ||
    event.conferenceData?.entryPoints?.find((p) => p.entryPointType === "video")?.uri ||
    null
  );
}
