import { requestAuth, failure, HttpError } from "@/lib/http";
import { adminClient } from "@/lib/supabase/server";
import { decryptToken, refreshCalendar } from "@/lib/calendar";
export const maxDuration = 60;
export async function GET(request: Request) {
  try {
    const { client, user } = await requestAuth(request);
    if (process.env.SUPABASE_SECRET_KEY)
      await refreshCalendar(user.id).catch(() => {});
    const [{ data: events, error }, { data: connection }] = await Promise.all([
      client
        .from("calendar_events")
        .select("id,title,starts_at,ends_at,meeting_url,attendees")
        .gt("ends_at", new Date().toISOString())
        .order("starts_at")
        .limit(250),
      client
        .from("calendar_connections")
        .select("email,updated_at,error")
        .maybeSingle(),
    ]);
    if (error) throw error;
    return Response.json(
      { events, connection },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  } catch (e) {
    return failure(e);
  }
}
export async function POST(request: Request) {
  try {
    const { client, user } = await requestAuth(request);
    const { data } = await client.rpc("is_murmur_editor");
    if (!data)
      throw new HttpError(403, "Sign in to Voice Notes to manage Calendar.");
    await refreshCalendar(user.id, true);
    return GET(new Request(request.url, { headers: request.headers }));
  } catch (e) {
    return failure(e);
  }
}
export async function DELETE(request: Request) {
  try {
    const { client, user } = await requestAuth(request);
    const { data } = await client.rpc("is_murmur_editor");
    if (!data)
      throw new HttpError(403, "Sign in to Voice Notes to manage Calendar.");
    const db = adminClient(),
      { data: credentials } = await db
        .from("calendar_credentials")
        .select("encrypted_refresh_token")
        .eq("user_id", user.id)
        .maybeSingle();
    if (credentials) {
      try {
        await fetch("https://oauth2.googleapis.com/revoke", {
          method: "POST",
          body: new URLSearchParams({
            token: decryptToken(credentials.encrypted_refresh_token),
          }),
          signal: AbortSignal.timeout(10000),
        });
      } catch {
        /* Removing our saved token still disconnects this app. */
      }
    }
    for (const table of [
      "calendar_credentials",
      "calendar_events",
      "calendar_connections",
    ]) {
      const { error } = await db.from(table).delete().eq("user_id", user.id);
      if (error) throw error;
    }
    return Response.json({ disconnected: true });
  } catch (e) {
    return failure(e);
  }
}
