import { requestAuth, requireEditor, failure, HttpError, limitedJSON } from "@/lib/http";
import { canBook } from "@/lib/google";
import { firstIssue, profileSchema } from "@/lib/scheduling/schema";
import { siteURL } from "@/lib/config";
const headers = { "Cache-Control": "private, no-store" };
// Everything the booking settings page shows, read with the person's own client.
export async function GET(request: Request) {
  try {
    const { client } = await requestAuth(request);
    const [profile, types, bookings, sources, connections] = await Promise.all([
      client.from("booking_profiles").select("*").maybeSingle(),
      client.from("event_types").select("*").order("position").order("created_at"),
      client
        .from("bookings")
        .select("id,event_type_id,title,status,starts_at,ends_at,guest_name,guest_email,guest_time_zone,answers,meeting_url,location_kind")
        .neq("status", "cancelled")
        .gt("ends_at", new Date().toISOString())
        .order("starts_at")
        .limit(100),
      client
        .from("calendar_sources")
        .select("connection_id,calendar_id,name,is_primary,can_write,selected")
        .order("is_primary", { ascending: false })
        .order("name"),
      client.from("calendar_connections").select("id,email,scopes").order("created_at"),
    ]);
    for (const r of [profile, types, bookings, sources, connections]) if (r.error) throw r.error;
    const accounts = (connections.data ?? []).map((c) => ({
      id: c.id as string,
      email: c.email as string | null,
      can_book: canBook(c.scopes ?? []),
    }));
    return Response.json(
      {
        profile: profile.data,
        types: types.data,
        bookings: bookings.data,
        accounts,
        calendars: sources.data,
        base_url: `${siteURL()}/book`,
      },
      { headers },
    );
  } catch (e) {
    return failure(e);
  }
}
export async function PUT(request: Request) {
  try {
    const { client, user } = await requireEditor(request);
    const parsed = profileSchema.safeParse(await limitedJSON(request, 200_000, "These settings are too large."));
    if (!parsed.success) throw new HttpError(400, firstIssue(parsed.error));
    const value = parsed.data;
    if (Boolean(value.destination_connection_id) !== Boolean(value.destination_calendar_id))
      throw new HttpError(400, "Choose the calendar that new bookings go into.");
    if (value.destination_connection_id) {
      const { data } = await client
        .from("calendar_sources")
        .select("can_write")
        .eq("connection_id", value.destination_connection_id)
        .eq("calendar_id", value.destination_calendar_id!)
        .maybeSingle();
      if (!data?.can_write)
        throw new HttpError(400, "Choose a calendar you can add events to.");
    }
    const { data, error } = await client
      .from("booking_profiles")
      .upsert({ ...value, user_id: user.id, updated_at: new Date().toISOString() })
      .select("*")
      .single();
    if (error?.code === "23505") throw new HttpError(409, "That link name is taken. Choose another.");
    if (error) throw error;
    return Response.json(data, { headers });
  } catch (e) {
    return failure(e);
  }
}
