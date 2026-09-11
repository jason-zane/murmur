import { requireEditor, failure, HttpError, limitedJSON } from "@/lib/http";
import { eventTypeSchema, firstIssue } from "@/lib/scheduling/schema";
export async function POST(request: Request) {
  try {
    const { client, user } = await requireEditor(request);
    const parsed = eventTypeSchema.safeParse(await limitedJSON(request, 50_000, "This meeting type is too large."));
    if (!parsed.success) throw new HttpError(400, firstIssue(parsed.error));
    const { data, error } = await client
      .from("event_types")
      .insert({ ...parsed.data, user_id: user.id })
      .select("*")
      .single();
    if (error?.code === "23505")
      throw new HttpError(409, "You already have a meeting type at that link. Choose another.");
    if (error) throw error;
    return Response.json(data, { status: 201 });
  } catch (e) {
    return failure(e);
  }
}
