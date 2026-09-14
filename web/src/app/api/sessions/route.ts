import { z } from "zod";
import { documentSchema } from "@/lib/documents";
import { requestAuth, failure, limitedJSON, HttpError } from "@/lib/http";
export async function GET(request: Request) {
  try {
    const { client } = await requestAuth(request);
    const params = new URL(request.url).searchParams;
    const offset = Math.max(0, Number(params.get("offset") || 0));
    if (!Number.isSafeInteger(offset))
      throw new HttpError(400, "Invalid page offset.");
    const { data, error } = await client
      .from("sessions")
      .select("id,title,started_at,updated_at,version,deleted_at,document")
      .order(params.get("order") === "recent" ? "started_at" : "id", {
        ascending: params.get("order") !== "recent",
      })
      .range(offset, offset + 49);
    if (error) throw error;
    return Response.json(
      { sessions: data, nextOffset: data.length === 50 ? offset + 50 : null },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  } catch (error) {
    return failure(error);
  }
}
export async function POST(request: Request) {
  try {
    const { client } = await requestAuth(request);
    const parsed = z
      .object({
        document: documentSchema,
        expectedVersion: z.number().int().nonnegative(),
        deleted: z.boolean().optional(),
      })
      .safeParse(await limitedJSON(request));
    if (!parsed.success)
      throw new HttpError(
        400,
        "The meeting document is invalid or still recording.",
      );
    const { data, error } = await client.rpc("put_session", {
      p_document: parsed.data.document,
      p_expected_version: parsed.data.expectedVersion,
      p_deleted: parsed.data.deleted ?? false,
    });
    if (error?.code === "PT409" || error?.code === "40001")
      throw new HttpError(
        409,
        "This note changed on another device. Your edit has been kept. Reload the latest copy before saving.",
      );
    if (error?.code === "42501")
      throw new HttpError(403, "This connection has read-only access.");
    if (error) throw error;
    return Response.json(data);
  } catch (error) {
    return failure(error);
  }
}
