import { timingSafeEqual } from "node:crypto";
import { dispatchOutbox } from "@/lib/mail/outbox";
import { failure } from "@/lib/http";
export const maxDuration=60;
export async function GET(request:Request) {
 const secret=process.env.CRON_SECRET,got=Buffer.from(request.headers.get("authorization") || ""),wanted=Buffer.from(`Bearer ${secret}`);
 if(!secret || got.length!==wanted.length || !timingSafeEqual(got,wanted)) return new Response("Unauthorised",{status:401});
 try {return Response.json(await dispatchOutbox());} catch(e) {return failure(e);}
}
