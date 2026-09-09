import { requestAuth, failure, HttpError } from "@/lib/http";
export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { client } = await requestAuth(request);
    const { id } = await params;
    const { data, error } = await client
      .from("sessions")
      .select("*")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    if (!data) throw new HttpError(404, "This note is not in your library.");
    return Response.json(data, {
      headers: { "Cache-Control": "private, no-store" },
    });
  } catch (e) {
    return failure(e);
  }
}
