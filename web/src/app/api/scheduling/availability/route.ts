import { z } from "zod";
import { requireEditor, failure, HttpError, limitedJSON } from "@/lib/http";
import { adminClient } from "@/lib/supabase/server";
import { scheduleSchema } from "@/lib/scheduling/schema";
export async function POST(request: Request) {
  try {
    const { user } = await requireEditor(request),
      body = await limitedJSON(request, 200000);
    const parsed = scheduleSchema
      .extend({ id: z.uuid().optional() })
      .safeParse(body);
    if (!parsed.success)
      throw new HttpError(400, parsed.error.issues[0].message);
    const { id, ...value } = parsed.data,
      db = adminClient();
    const query = id
      ? db
          .from("availability_schedules")
          .update(value)
          .eq("id", id)
          .eq("user_id", user.id)
      : db
          .from("availability_schedules")
          .insert({ ...value, user_id: user.id });
    const { data, error } = await query.select("*").maybeSingle();
    if (error?.code === "23505")
      throw new HttpError(409, "A schedule with that name already exists.");
    if (error) throw error;
    if (!data) throw new HttpError(404, "Schedule not found.");
    return Response.json(data);
  } catch (e) {
    return failure(e);
  }
}
export async function DELETE(request: Request) {
  try {
    const { user } = await requireEditor(request),
      id = z.uuid().parse(new URL(request.url).searchParams.get("id"));
    const { data, error } = await adminClient()
      .from("availability_schedules")
      .delete()
      .eq("id", id)
      .eq("user_id", user.id)
      .select("id");
    if (error?.code === "23503")
      throw new HttpError(
        409,
        "This schedule is used by a meeting type. Choose a different schedule for that type before deleting it.",
      );
    if (error) throw error;
    if (!data?.length) throw new HttpError(404, "Schedule not found.");
    return Response.json({ removed: true });
  } catch (e) {
    return failure(e);
  }
}
