import { z } from "zod";
import { failure, HttpError, limitedJSON } from "@/lib/http";
import { cancelBooking, guestView, rateLimit, rescheduleBooking, sameOrigin } from "@/lib/scheduling/booking";
import { firstIssue, timeZoneSchema } from "@/lib/scheduling/schema";
// The guest's private link carries its token after #, so it never reaches server logs.
// The page sends it here in the request body.
const schema = z.discriminatedUnion("action", [
  z.object({ action: z.literal("view"), token: z.string().min(20).max(100) }),
  z.object({
    action: z.literal("cancel"),
    token: z.string().min(20).max(100),
    reason: z.string().max(1000).optional(),
  }),
  z.object({
    action: z.literal("reschedule"),
    token: z.string().min(20).max(100),
    start: z.iso.datetime({ offset: true }),
    time_zone: timeZoneSchema,
  }),
]);
export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    sameOrigin(request);
    await rateLimit(request, "manage", 30, 600);
    const { id } = await params;
    const parsed = schema.safeParse(await limitedJSON(request, 10_000, "That request is too large."));
    if (!parsed.success) throw new HttpError(400, firstIssue(parsed.error));
    const body = parsed.data;
    const result =
      body.action === "view"
        ? await guestView(id, body.token)
        : body.action === "cancel"
          ? await cancelBooking(id, { token: body.token }, body.reason)
          : await rescheduleBooking(id, body.token, body.start, body.time_zone);
    return Response.json(result, { headers: { "Cache-Control": "no-store" } });
  } catch (e) {
    return failure(e);
  }
}
