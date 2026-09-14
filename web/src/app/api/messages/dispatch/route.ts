import { timingSafeEqual } from "node:crypto";
import { runMessages } from "@/lib/messages/service";
import { failure } from "@/lib/http";
export const maxDuration = 60;
export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  const got = Buffer.from(request.headers.get("authorization") || ""),
    wanted = Buffer.from(`Bearer ${secret}`);
  if (!secret || got.length !== wanted.length || !timingSafeEqual(got, wanted))
    return new Response("Unauthorised", { status: 401 });
  try {
    return Response.json(await runMessages());
  } catch (e) {
    return failure(e);
  }
}
