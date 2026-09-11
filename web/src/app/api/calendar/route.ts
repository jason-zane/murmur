import { z } from "zod";
import { requestAuth, requireEditor, failure, HttpError } from "@/lib/http";
import { agenda, disconnect, refreshCalendar } from "@/lib/calendar";
export const maxDuration = 60;
const headers = { "Cache-Control": "private, no-store" };
export async function GET(request: Request) {
  try {
    const { client, user } = await requestAuth(request);
    if (process.env.SUPABASE_SECRET_KEY)
      await refreshCalendar(user.id).catch(() => {});
    return Response.json(await agenda(client), { headers });
  } catch (e) {
    return failure(e);
  }
}
// Each account's own error is stored on it, so a refresh reports per account.
export async function POST(request: Request) {
  try {
    const { client, user } = await requireEditor(
      request,
      "Sign in to Voice Notes to manage Calendar.",
    );
    await refreshCalendar(user.id, true).catch(() => {});
    return Response.json(await agenda(client), { headers });
  } catch (e) {
    return failure(e);
  }
}
export async function DELETE(request: Request) {
  try {
    const { user } = await requireEditor(
      request,
      "Sign in to Voice Notes to manage Calendar.",
    );
    const id = new URL(request.url).searchParams.get("connection");
    if (id && !z.uuid().safeParse(id).success)
      throw new HttpError(400, "That calendar account isn’t connected.");
    await disconnect(user.id, id ?? undefined);
    return Response.json({ disconnected: true });
  } catch (e) {
    return failure(e);
  }
}
