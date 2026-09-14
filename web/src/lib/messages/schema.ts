import { z } from "zod";
export const VARIABLES = [
  "guest_name",
  "meeting_title",
  "meeting_time",
  "join_link",
] as const;
export function validTemplate(text: string) {
  const tokens = [...text.matchAll(/\{\{(.*?)\}\}/g)].map((m) => m[1].trim());
  return (
    tokens.every((t) => (VARIABLES as readonly string[]).includes(t)) &&
    !text.replace(/\{\{.*?\}\}/g, "").match(/\{\{|\}\}/)
  );
}
const subject = z
  .string()
  .trim()
  .min(1)
  .max(200)
  .refine((s) => !/[\r\n]/.test(s), "Use one line for the subject.");
export const ruleSchema = z.object({
  event_type_id: z.uuid(),
  kind: z.enum(["preparation", "reminder", "thank_you"]),
  offset_minutes: z.number().int().min(0).max(43200),
  subject: subject.refine(
    validTemplate,
    "Use the supported message variables.",
  ),
  body: z
    .string()
    .trim()
    .min(1)
    .max(10000)
    .refine(validTemplate, "Use the supported message variables."),
  enabled: z.boolean(),
});
export const draftSchema = z.object({
  booking_id: z.uuid(),
  subject,
  body: z.string().trim().min(1).max(10000),
});
export function renderTemplate(
  text: string,
  values: Record<(typeof VARIABLES)[number], string>,
) {
  if (!validTemplate(text))
    throw new Error("This template contains an unsupported variable.");
  return text.replace(
    /\{\{(.*?)\}\}/g,
    (_, key: string) => values[key.trim() as keyof typeof values],
  );
}
export function messageDue(
  kind: string,
  start: string,
  end: string,
  offset: number,
) {
  return new Date(
    new Date(kind === "thank_you" ? end : start).getTime() +
      (kind === "thank_you" ? 1 : -1) * offset * 60000,
  ).toISOString();
}
export function skipReason(
  message: { booking_start: string; kind: string },
  booking: { status: string; starts_at: string; attendance: string },
  enabled: boolean,
) {
  if (booking.status !== "confirmed")
    return "Booking cancelled or not confirmed.";
  if (
    booking.starts_at !== message.booking_start &&
    Date.parse(booking.starts_at) !== Date.parse(message.booking_start)
  )
    return "Booking moved; this message belongs to the previous time.";
  if (!enabled) return "This message recipe is switched off.";
  if (message.kind === "thank_you" && booking.attendance !== "completed")
    return "Meeting has not been marked completed.";
  return null;
}
/** Plain text MIME. Header inputs are validated rather than accepting arbitrary headers. */
export function mimeMessage(
  from: string,
  to: string,
  subject: string,
  body: string,
  id: string,
) {
  if (
    !z.email().safeParse(from).success ||
    !z.email().safeParse(to).success ||
    /[\r\n]/.test(subject)
  )
    throw new Error("Check the sender, recipient and subject.");
  const encoded = Buffer.from(subject).toString("base64");
  return Buffer.from(
    `From: ${from}\r\nTo: ${to}\r\nSubject: =?UTF-8?B?${encoded}?=\r\nMessage-ID: <${id}@voice-notes.invalid>\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${
      Buffer.from(body)
        .toString("base64")
        .match(/.{1,76}/g)
        ?.join("\r\n") || ""
    }`,
  ).toString("base64url");
}

/** Prepare a private draft from explicitly labelled decisions/actions only. Never include
 * the transcript, guest answers, personal-note sections or unrelated summary sections. */
export function followUpDraft(note: string, guest: string) {
  const sections: string[] = [];
  let include = false;
  for (const line of note.split("\n")) {
    const heading = line.match(/^#{1,6}\s+(.+?)\s*#*$/);
    if (heading) {
      include =
        /^(decisions|action items|actions|next steps|agreed actions)$/i.test(
          heading[1].trim(),
        );
      if (include) sections.push(`\n${heading[1]}\n`);
      continue;
    }
    if (include) sections.push(line);
  }
  return `Hi ${guest},\n\nThank you for your time.\n${sections.length ? "\n" + sections.join("\n").trim() + "\n" : "\n"}`.slice(
    0,
    10000,
  );
}
