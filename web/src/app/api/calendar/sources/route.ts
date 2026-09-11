import { z } from "zod";
import { requireEditor, failure, HttpError, limitedJSON } from "@/lib/http";
import { agenda, refreshCalendar } from "@/lib/calendar";
export const maxDuration = 60;
// Chooses whether one calendar appears in the agenda and blocks booking times.
export async function PATCH(request: Request) {
  try {
    const { client, user } = await requireEditor(
      request,
      "Sign in to Voice Notes to manage Calendar.",
    );
    const parsed = z
      .object({
        connection_id: z.uuid(),
        calendar_id: z.string().min(1).max(1024),
        selected: z.boolean(),
      })
      .safeParse(await limitedJSON(request, 10_000, "That request is too large."));
    if (!parsed.success) throw new HttpError(400, "Choose a calendar.");
    const { connection_id, calendar_id, selected } = parsed.data;
    const { data, error } = await client
      .from("calendar_sources")
      .update({ selected })
      .eq("connection_id", connection_id)
      .eq("calendar_id", calendar_id)
      .select("calendar_id");
    if (error) throw error;
    if (!data?.length) throw new HttpError(404, "That calendar isn’t connected.");
    await refreshCalendar(user.id, true).catch(() => {});
    return Response.json(await agenda(client), {
      headers: { "Cache-Control": "private, no-store" },
    });
  } catch (e) {
    return failure(e);
  }
}
