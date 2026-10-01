import {timingSafeEqual} from "node:crypto";
import {runCalendarJobs} from "@/lib/calendar-jobs";
import {renewCalendarChannels} from "@/lib/calendar-push";
import {adminClient} from "@/lib/supabase/server";
import {failure} from "@/lib/http";
export const maxDuration=60;
export async function GET(request:Request) {
 const secret=process.env.CRON_SECRET,got=Buffer.from(request.headers.get("authorization") || ""),wanted=Buffer.from(`Bearer ${secret}`);
 if(!secret || got.length!==wanted.length || !timingSafeEqual(got,wanted)) return new Response("Unauthorised",{status:401});
 try {const {error}=await adminClient().rpc("queue_calendar_reconciliation",{p_owner:null});if(error) throw error;const [jobs,channels]=await Promise.all([runCalendarJobs(),renewCalendarChannels()]);return Response.json({...jobs,...channels});}catch(e){return failure(e);}
}
