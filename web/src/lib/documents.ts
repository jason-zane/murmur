import { z } from "zod";
const short = z.string().max(2000);
export const sessionID = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/);
export const documentSchema = z.object({
  session: z.object({
    id: sessionID,
    title: z.string().min(1).max(1000),
    startedAt: z.iso.datetime({ offset: true }),
    endedAt: z.iso.datetime({ offset: true }).nullable().optional(),
    state: z.enum(["raw", "noted"]),
    app: short.nullable().optional(),
    bundleID: short.nullable().optional(),
    calendarEventID: short.nullable().optional(),
    attendees: z
      .array(z.object({ name: short, email: short.nullable().optional() }))
      .max(1000),
    speakers: z.array(short).max(1000),
    engine: short,
    segmentCount: z.number().int().nonnegative(),
    duration: z.number().nonnegative().max(604800),
    pinned: z.boolean().nullable().optional(),
    noteSource: short.nullable().optional(),
    summaryTemplate: short.nullable().optional(),
    // Answers a guest gave on the booking page. Not said in the meeting, not written by you.
    booking: z
      .object({
        eventType: short,
        guestName: short,
        guestEmail: short.nullable().optional(),
        answers: z
          .array(z.object({ question: short, answer: z.string().max(4000) }))
          .max(20),
      })
      .nullable()
      .optional(),
  }),
  transcript: z
    .array(
      z.object({
        id: z.uuid(),
        start: z.number().nonnegative(),
        end: z.number().nonnegative(),
        source: z.enum(["you", "call"]),
        speaker: short.nullable().optional(),
        text: z.string().max(100000),
      }),
    )
    .max(100000),
  bullets: z
    .array(
      z.object({
        id: z.uuid(),
        at: z.number().nonnegative(),
        text: z.string().max(100000),
      }),
    )
    .max(10000),
  note: z.string().max(2000000).nullable().default(null),
});
export type MeetingDocument = z.infer<typeof documentSchema>;
export type CloudSession = {
  id: string;
  title: string;
  started_at: string;
  updated_at: string;
  version: number;
  deleted_at: string | null;
  document: MeetingDocument;
};
export type CalendarMeeting = {
  id: string;
  title: string;
  starts_at: string;
  ends_at: string;
  meeting_url: string | null;
  attendees: { name: string; email?: string }[];
  booking?: {
    id: string;
    event_type: string;
    template: string;
    guest_name: string;
    guest_email: string;
    answers: { question: string; answer: string }[];
  };
};
export function newDocument(title = "Untitled note"): MeetingDocument {
  const now = new Date().toISOString();
  return {
    session: {
      id: `note-${crypto.randomUUID()}`,
      title,
      startedAt: now,
      endedAt: now,
      state: "noted",
      attendees: [],
      speakers: [],
      engine: "Notes",
      segmentCount: 0,
      duration: 0,
      noteSource: "You",
    },
    transcript: [],
    bullets: [],
    note: "",
  };
}
export function preview(document: MeetingDocument) {
  return (
    document.note ||
    document.bullets.map((b) => b.text).join(" ") ||
    document.transcript.map((s) => s.text).join(" ")
  )
    .replace(/[#*\[\]`>_]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 190);
}
export function matches(document: MeetingDocument, query: string) {
  const haystack = [
    document.session.title,
    document.note,
    ...document.session.speakers,
    ...document.bullets.map((b) => b.text),
    ...document.transcript.map((s) => s.text),
  ]
    .join("\n")
    .toLocaleLowerCase();
  return query
    .trim()
    .toLocaleLowerCase()
    .split(/\s+/)
    .every((term) => haystack.includes(term));
}
export function meetingURL(value: string | undefined | null) {
  if (!value) return null;
  try {
    const u = new URL(value);
    return u.protocol === "https:" &&
      !u.username &&
      !u.password &&
      [
        "meet.google.com",
        "zoom.us",
        "teams.microsoft.com",
        "teams.live.com",
      ].some(
        (h) =>
          u.hostname === h ||
          (h === "zoom.us" && u.hostname.endsWith(".zoom.us")),
      )
      ? u.href
      : null;
  } catch {
    return null;
  }
}
