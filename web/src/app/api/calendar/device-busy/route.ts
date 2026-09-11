import { z } from "zod";
import { requireEditor, failure, HttpError, limitedJSON } from "@/lib/http";
// The Mac shares when its own calendars (iCloud, Exchange) are busy, so booking pages can
// avoid those times. Only start and end are sent: no titles, places or attendees.
const schema = z.object({
  blocks: z
    .array(
      z.object({
        start: z.iso.datetime({ offset: true }),
        end: z.iso.datetime({ offset: true }),
      }),
    )
    .max(2000),
});
export async function PUT(request: Request) {
  try {
    const { client, user } = await requireEditor(
      request,
      "Only your Mac can share its busy times.",
    );
    const parsed = schema.safeParse(
      await limitedJSON(request, 400_000, "Too many busy times to share at once."),
    );
    if (!parsed.success) throw new HttpError(400, "These busy times are invalid.");
    const now = Date.now();
    const blocks = parsed.data.blocks
      .map((b) => ({ start: new Date(b.start), end: new Date(b.end) }))
      .filter(
        (b) =>
          b.end > b.start &&
          b.end.getTime() > now - 86_400_000 &&
          b.start.getTime() < now + 120 * 86_400_000,
      )
      .map((b) => ({ start: b.start.toISOString(), end: b.end.toISOString() }));
    const { error } = await client.from("device_busy_times").upsert({
      user_id: user.id,
      blocks,
      uploaded_at: new Date().toISOString(),
    });
    if (error?.code === "42501")
      throw new HttpError(403, "Only your Mac can share its busy times.");
    if (error) throw error;
    return Response.json({ shared: blocks.length });
  } catch (e) {
    return failure(e);
  }
}
