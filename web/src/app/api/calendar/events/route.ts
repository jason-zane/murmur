import { after } from "next/server";
import { runCalendarJobs } from "@/lib/calendar-jobs";
import { z } from "zod";
import { requireEditor,failure,HttpError,limitedJSON } from "@/lib/http";
import { calendarRange,rangeSchema,eventInput,ownCalendar,workspaceEvent } from "@/lib/calendar-workspace";
import { GoogleError } from "@/lib/google";
export const maxDuration=60;
const headers={"Cache-Control":"private, no-store"};
const eventFailure=(e:unknown)=>failure(e instanceof z.ZodError?new HttpError(400,e.issues[0].message):e instanceof GoogleError?new HttpError(e.status===412?409:e.status===401?403:e.status>=500?502:e.status,e.message):e);
export async function GET(request:Request) {
 try {
  const {client,user}=await requireEditor(request),p=new URL(request.url).searchParams;
  if(p.get("id")) {
   const {api,source}=await ownCalendar(user.id,z.uuid().parse(p.get("account")),z.string().min(1).max(1024).parse(p.get("calendar")));
   const id=z.string().min(1).max(1024).parse(p.get("id"));
   return Response.json({event:workspaceEvent(await api.getEvent(source.calendar_id,id),source.connection_id,source.calendar_id,source.time_zone || "UTC")},{headers});
  }
  const range=rangeSchema.safeParse({from:p.get("from"),to:p.get("to")});
  if(!range.success) throw new HttpError(400,range.error.issues[0].message);
  const page=await calendarRange(client,user.id,range.data.from,range.data.to,p.get("refresh")==="1");
  if(page.pending) after(()=>runCalendarJobs(user.id).then(()=>{}).catch(()=>{}));
  return Response.json(page,{headers});
 } catch(e) {return eventFailure(e);}
}
export async function PATCH(request:Request) {
 try {
  const {user}=await requireEditor(request),v=z.object({connection_id:z.uuid(),calendar_id:z.string().min(1).max(1024),id:z.string().min(1).max(1024),etag:z.string().min(1).max(1024),response:z.enum(["accepted","tentative","declined"])}).parse(await limitedJSON(request,10000));
  const {api}=await ownCalendar(user.id,v.connection_id,v.calendar_id,true),current=await api.getEvent(v.calendar_id,v.id);
  if(current.etag!==v.etag) throw new HttpError(409,"This invitation changed. Reload it before responding.");
  if(!current.attendees?.some(a=>a.self)) throw new HttpError(403,"This calendar copy does not have an invitation for you.");
  const event=await api.patchEvent(v.calendar_id,v.id,{attendees:current.attendees.map(a=>a.self?{...a,responseStatus:v.response}:a)},v.etag);
  return Response.json({event},{headers});
 } catch(e) {return eventFailure(e);}
}
export async function POST(request:Request) {
 try {
  const {user}=await requireEditor(request),parsed=eventInput.safeParse(await limitedJSON(request,50000));
  if(!parsed.success) throw new HttpError(400,parsed.error.issues[0].message);
  const v=parsed.data,{api}=await ownCalendar(user.id,v.connection_id,v.calendar_id,true);
  const current=v.id?await api.getEvent(v.calendar_id,v.id):null;
  if(current && current.etag!==v.etag) throw new HttpError(409,"This event changed in another app. Reload it before editing.");
  const attendees=new Map((current?.attendees || []).filter(a=>a.email).map(a=>[a.email!.toLowerCase(),a]));
  const body={summary:v.title,description:v.description,location:v.location,
   start:v.all_day?{date:v.start}:{dateTime:v.start,timeZone:v.time_zone},end:v.all_day?{date:v.end}:{dateTime:v.end,timeZone:v.time_zone},
   attendees:v.attendees.map(email=>attendees.get(email.toLowerCase()) || {email}),...(v.reminders?{reminders:v.reminders}:{}),...(v.recurrence?{recurrence:v.recurrence}:{})};
  if(v.id && !v.etag) throw new HttpError(409,"Reload this event before editing it.");
  const event=v.id?await api.patchEvent(v.calendar_id,v.id,body,v.etag):await api.insertEvent(v.calendar_id,body);
  return Response.json({event},{headers});
 } catch(e) {return eventFailure(e);}
}
export async function DELETE(request:Request) {
 try {
  const {user}=await requireEditor(request),v=z.object({connection_id:z.uuid(),calendar_id:z.string().min(1).max(1024),id:z.string().min(1).max(1024),etag:z.string().min(1).max(1024)}).parse(await limitedJSON(request,10000));
  const {api}=await ownCalendar(user.id,v.connection_id,v.calendar_id,true);
  await api.deleteEvent(v.calendar_id,v.id,v.etag);
  return Response.json({deleted:true},{headers});
 } catch(e) {return eventFailure(e);}
}
