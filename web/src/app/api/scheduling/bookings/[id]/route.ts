import { z } from "zod";
import { requireEditor, failure, HttpError, limitedJSON } from "@/lib/http";
import { cancelBooking, rescheduleBooking } from "@/lib/scheduling/booking";
import { timeZoneSchema } from "@/lib/scheduling/schema";
import { adminClient } from "@/lib/supabase/server";
import { bookingOperation } from "@/lib/scheduling/operation";
export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { user } = await requireEditor(request),
      { id } = await params;
    if (!z.uuid().safeParse(id).success)
      throw new HttpError(404, "Booking not found.");
    const body = z
      .discriminatedUnion("action", [
        z.object({
          action: z.literal("cancel"),
          reason: z.string().max(1000).optional(),
        }),
        z.object({
          action: z.literal("reschedule"),
          start: z.iso.datetime({ offset: true }),
          time_zone: timeZoneSchema,
        }),
        z.object({
          action: z.literal("attendance"),
          attendance: z.enum(["completed", "no_show", "unknown"]),
        }),
      ])
      .safeParse(await limitedJSON(request, 10000));
    if (!body.success)
      throw new HttpError(400, "Check the booking action and time.");
    if (body.data.action === "cancel")
      return Response.json(
        await cancelBooking(id, { hostID: user.id }, body.data.reason),
      );
    if (body.data.action === "reschedule")
      return Response.json(
        await rescheduleBooking(
          id,
          { hostID: user.id },
          body.data.start,
          body.data.time_zone,
        ),
      );
    const attendance = body.data.attendance;
    return Response.json(
      await bookingOperation(id, async () => {
        const { data, error } = await adminClient()
          .from("bookings")
          .update({ attendance })
          .eq("id", id)
          .eq("user_id", user.id)
          .eq("status", "confirmed")
          .lte("ends_at", new Date().toISOString())
          .select("id")
          .maybeSingle();
        if (error) throw error;
        if (!data)
          throw new HttpError(
            409,
            "Mark attendance after the meeting has ended.",
          );
        return { saved: true };
      }),
    );
  } catch (e) {
    return failure(e);
  }
}
export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { user } = await requireEditor(request),
      id = z.uuid().parse((await params).id);
    const { data, error } = await adminClient()
      .from("bookings")
      .delete()
      .eq("id", id)
      .eq("user_id", user.id)
      .eq("status", "cancelled")
      .select("id");
    if (error) throw error;
    if (!data?.length)
      throw new HttpError(
        409,
        "Only a cancelled booking can be removed from history.",
      );
    return Response.json({ removed: true });
  } catch (e) {
    return failure(e);
  }
}
