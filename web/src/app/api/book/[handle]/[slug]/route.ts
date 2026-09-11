import { failure, HttpError, limitedJSON } from "@/lib/http";
import { isTimeZone } from "@/lib/scheduling/availability";
import { createBooking, rateLimit, sameOrigin, slotsFor } from "@/lib/scheduling/booking";
import { bookingRequestSchema, firstIssue } from "@/lib/scheduling/schema";
export const maxDuration = 60;
// Public: open times for one meeting type. No sign-in; rate limited per address.
export async function GET(
  request: Request,
  { params }: { params: Promise<{ handle: string; slug: string }> },
) {
  try {
    await rateLimit(request, "slots", 120, 60);
    const { handle, slug } = await params;
    const q = new URL(request.url).searchParams;
    const from = new Date(q.get("from") || ""),
      to = new Date(q.get("to") || ""),
      timeZone = q.get("timeZone") || "UTC";
    if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()))
      throw new HttpError(400, "Choose the dates to show.");
    if (!isTimeZone(timeZone)) throw new HttpError(400, "Choose a valid time zone.");
    const slots = await slotsFor(handle, slug, from, to, timeZone);
    return Response.json(
      { slots: slots.map((s) => s.toISOString()) },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (e) {
    return failure(e);
  }
}
// Public: books a time. The invitation comes from the host's own calendar.
export async function POST(
  request: Request,
  { params }: { params: Promise<{ handle: string; slug: string }> },
) {
  try {
    sameOrigin(request);
    await rateLimit(request, "book", 10, 600);
    const { handle, slug } = await params;
    const parsed = bookingRequestSchema.safeParse(
      await limitedJSON(request, 50_000, "That booking is too large."),
    );
    if (!parsed.success) throw new HttpError(400, firstIssue(parsed.error));
    return Response.json(await createBooking(handle, slug, parsed.data), {
      status: 201,
      headers: { "Cache-Control": "no-store" },
    });
  } catch (e) {
    return failure(e);
  }
}
