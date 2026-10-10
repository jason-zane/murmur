import {after} from "next/server";
import {acceptCalendarNotification} from "@/lib/calendar-push";
import {runCalendarJobs} from "@/lib/calendar-jobs";
import {failure} from "@/lib/http";
export const maxDuration=60;
export async function POST(request:Request) {
 try {
  const owner=await acceptCalendarNotification(request.headers);
  if(!owner) return new Response("Unauthorised",{status:401});
  after(async()=>{try {await runCalendarJobs(owner);}catch{/* Durable jobs survive worker failure. */}});
  return new Response(null,{status:204});
 } catch(e) {return failure(e);}
}
