import { requireEditor, failure, HttpError, limitedJSON } from "@/lib/http";
import { effectiveFollowUp, followUpSourceID, followUpWrite, type SavedFollowUp } from "@/lib/follow-up/drafts";

type Context = { params: Promise<{ id: string }> };
const headers = { "Cache-Control": "private, no-store" };
async function sourceID(context: Context) {
  const parsed = followUpSourceID.safeParse((await context.params).id);
  if (!parsed.success) throw new HttpError(400, "Invalid note identifier.");
  return parsed.data;
}
function failed(error: unknown) {
  const response = failure(error);
  response.headers.set("Cache-Control", headers["Cache-Control"]);
  return response;
}

export async function GET(request: Request, context: Context) {
  try {
    if (process.env.FOLLOW_UP_DRAFTS_ENABLED !== "true") throw new HttpError(404, "Follow-up drafts are not available.");
    const { client } = await requireEditor(request);
    const id = await sourceID(context);
    // One database snapshot; no stale approval between separate note/draft reads.
    const result = await client.rpc("get_follow_up_draft", { p_session_id: id });
    if (result.error) throw result.error;
    if (!result.data) throw new HttpError(404, "This note is not in your library.");
    return Response.json(effectiveFollowUp(result.data.draft as SavedFollowUp | null, result.data.sourceVersion), { headers });
  } catch (error) { return failed(error); }
}

export async function PUT(request: Request, context: Context) {
  try {
    if (process.env.FOLLOW_UP_DRAFTS_ENABLED !== "true") throw new HttpError(404, "Follow-up drafts are not available.");
    const { client } = await requireEditor(request);
    const id = await sourceID(context);
    const parsed = followUpWrite.safeParse(await limitedJSON(request, 100000, "This follow-up draft is too large to save."));
    if (!parsed.success) throw new HttpError(400, "Check the draft, source evidence and unresolved details before saving.");
    // The database derives ownership from the verified JWT. No owner, provider,
    // sender, dispatch status or credential can be supplied in the request.
    const { data, error } = await client.rpc("put_follow_up_draft", {
      p_session_id: id, p_document: parsed.data.document, p_expected_version: parsed.data.expectedVersion,
    });
    if (error?.code === "PT409") throw new HttpError(409, "This draft or its source note changed. Keep your edits and load the latest copy before saving.");
    if (error?.code === "PT404") throw new HttpError(404, "This note is not in your library.");
    if (error?.code === "42501") throw new HttpError(403, "Only your signed-in Concourse app can change follow-up drafts.");
    if (error?.code === "22023") throw new HttpError(400, "The draft evidence does not match the source note, or the draft is invalid.");
    if (error) throw error;
    return Response.json({ draft: data }, { headers });
  } catch (error) { return failed(error); }
}
