import { validateTypeReferences } from "@/lib/scheduling/schedules";
import { z } from "zod";
import { requireEditor, failure, HttpError, limitedJSON } from "@/lib/http";
import { eventTypeSchema, firstIssue } from "@/lib/scheduling/schema";
async function id(params: Promise<{ id: string }>) {
  const { id } = await params;
  if (!z.uuid().safeParse(id).success)
    throw new HttpError(404, "This meeting type doesn’t exist.");
  return id;
}
export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { client } = await requireEditor(request);
    const parsed = eventTypeSchema.safeParse(
      await limitedJSON(request, 50_000, "This meeting type is too large."),
    );
    if (!parsed.success) throw new HttpError(400, firstIssue(parsed.error));
    await validateTypeReferences(client, parsed.data);
    const { data, error } = await client
      .from("event_types")
      .update({ ...parsed.data, updated_at: new Date().toISOString() })
      .eq("id", await id(params))
      .select("*")
      .maybeSingle();
    if (error?.code === "23505")
      throw new HttpError(
        409,
        "You already have a meeting type at that link. Choose another.",
      );
    if (error) throw error;
    if (!data) throw new HttpError(404, "This meeting type doesn’t exist.");
    return Response.json(data);
  } catch (e) {
    return failure(e);
  }
}
// Existing bookings keep their times; they no longer link back to the removed type.
export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { client } = await requireEditor(request);
    const { data, error } = await client
      .from("event_types")
      .delete()
      .eq("id", await id(params))
      .select("id");
    if (error) throw error;
    if (!data?.length)
      throw new HttpError(404, "This meeting type doesn’t exist.");
    return Response.json({ removed: true });
  } catch (e) {
    return failure(e);
  }
}
