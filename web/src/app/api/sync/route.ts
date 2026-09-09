import { requestAuth, failure, HttpError } from "@/lib/http";
export async function GET(request: Request) {
  try {
    const { client } = await requestAuth(request);
    const offset = Number(new URL(request.url).searchParams.get("offset") || 0);
    if (!Number.isSafeInteger(offset) || offset < 0)
      throw new HttpError(400, "Invalid page offset.");
    const { data, error } = await client
      .from("sessions")
      .select("id,version,deleted_at")
      .order("id")
      .range(offset, offset + 199);
    if (error) throw error;
    return Response.json(
      { sessions: data, nextOffset: data.length === 200 ? offset + 200 : null },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  } catch (e) {
    return failure(e);
  }
}
