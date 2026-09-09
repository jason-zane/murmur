import { bearerClient, serverClient } from "./supabase/server";
import { siteURL } from "./config";
export async function requestAuth(request: Request) {
  const header = request.headers.get("authorization");
  const token = header?.startsWith("Bearer ") ? header.slice(7) : null;
  const client = token ? bearerClient(token) : await serverClient();
  const { data, error } = token
    ? await client.auth.getUser(token)
    : await client.auth.getUser();
  if (error || !data.user)
    throw new HttpError(401, "Sign in to Voice Notes to continue.");
  if (
    !token &&
    !["GET", "HEAD"].includes(request.method) &&
    request.headers.get("origin") !== siteURL()
  )
    throw new HttpError(403, "This request must come from Voice Notes.");
  return { client, user: data.user };
}
export class HttpError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}
export function failure(error: unknown) {
  if (error instanceof HttpError)
    return Response.json({ error: error.message }, { status: error.status });
  console.error(
    "Voice Notes request failed",
    error instanceof Error ? error.message : "Unknown error",
  );
  return Response.json(
    { error: "Voice Notes could not complete this request. Try again shortly." },
    { status: 500 },
  );
}
export async function limitedJSON(request: Request, limit = 8_000_000) {
  if (Number(request.headers.get("content-length") || 0) > limit)
    throw new HttpError(413, "This meeting is too large to sync.");
  const reader = request.body?.getReader();
  if (!reader) throw new HttpError(400, "Missing request body.");
  let bytes = 0;
  const chunks: Uint8Array[] = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.length;
    if (bytes > limit) {
      await reader.cancel();
      throw new HttpError(413, "This meeting is too large to sync.");
    }
    chunks.push(value);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new HttpError(400, "Invalid JSON.");
  }
}
