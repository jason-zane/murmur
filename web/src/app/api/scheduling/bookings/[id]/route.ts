import { z } from "zod";
import { requireEditor, failure, HttpError, limitedJSON } from "@/lib/http";
import { cancelBooking } from "@/lib/scheduling/booking";
// The host cancels a booking. Google tells the guest, from the host's calendar.
export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { user } = await requireEditor(request);
    const { id } = await params;
    if (!z.uuid().safeParse(id).success) throw new HttpError(404, "This booking isn’t in your calendar.");
    const parsed = z
      .object({ action: z.literal("cancel"), reason: z.string().max(1000).optional() })
      .safeParse(await limitedJSON(request, 10_000, "That request is too large."));
    if (!parsed.success) throw new HttpError(400, "Choose what to do with this booking.");
    return Response.json(await cancelBooking(id, { hostID: user.id }, parsed.data.reason));
  } catch (e) {
    return failure(e);
  }
}
