import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import { adminClient } from "./supabase/server";
import { accessToken, connectionsFor } from "./calendar";
import { google, canReadEvents, type GoogleEvent } from "./google";
import { queueCalendarRanges } from "./calendar-jobs";
import { calendarContext } from "./calendar-context";
import { HttpError } from "./http";
import dayjs from "./scheduling/dayjs";
import type { CalendarMeeting } from "./documents";
import { meetingURL } from "./documents";

export const rangeSchema = z.object({
  from: z.iso.datetime({offset:true}), to: z.iso.datetime({offset:true}),
}).refine(v => Date.parse(v.to)>Date.parse(v.from) && Date.parse(v.to)-Date.parse(v.from)<=93*86400000,
 {message:"Choose a calendar period of up to three months."});
export type WorkspaceEvent = CalendarMeeting & {
 stable_id: string; ical_uid: string | null; details: EventDetails; legacy_id_unique?:boolean;
};
export type EventDetails = {
 all_day?: boolean; start_date?: string; end_date?: string; time_zone?: string;
 description?: string; location?: string; html_url?: string; status?: string;
 response?: string; availability?: string; recurring_id?: string; original_start?: string;
 etag?: string; organiser?: string; recurrence?:string[]; reminders?:GoogleEvent["reminders"];
};
export function eventIdentity(account: string, calendar: string, id: string) {
 return `google:${account}:${encodeURIComponent(calendar)}:${encodeURIComponent(id)}`;
}
export function workspaceEvent(e: GoogleEvent, account: string, calendar: string, timeZone="UTC"): WorkspaceEvent | null {
 if(e.status === "cancelled") return null;
 const allDay=Boolean(e.start?.date);
 const start=allDay ? dayjs.tz(e.start!.date!,timeZone).toISOString() : e.start?.dateTime;
 const end=allDay ? dayjs.tz(e.end?.date || "",timeZone).toISOString() : e.end?.dateTime;
 if(!start || !end || !Number.isFinite(Date.parse(start)) || !Number.isFinite(Date.parse(end)) || Date.parse(end)<=Date.parse(start)) return null;
 return {id:e.id,stable_id:eventIdentity(account,calendar,e.id),connection_id:account,calendar_id:calendar,
  ical_uid:e.iCalUID || null,title:e.summary || "Untitled event",starts_at:start,ends_at:end,
  meeting_url:meetingURL(e.hangoutLink || e.conferenceData?.entryPoints?.find(p=>p.entryPointType==="video")?.uri),
  attendees:(e.attendees || []).map(a=>({name:a.displayName || a.email || "Guest",...(a.email?{email:a.email}:{})})),
  details:{all_day:allDay,start_date:e.start?.date,end_date:e.end?.date,time_zone:e.start?.timeZone || timeZone,
   description:e.description,location:e.location,html_url:e.htmlLink,status:e.status,
   response:e.attendees?.find(a=>a.self)?.responseStatus,availability:e.transparency,
   recurring_id:e.recurringEventId,original_start:e.originalStartTime?.dateTime || e.originalStartTime?.date,
   etag:e.etag,organiser:e.organizer?.email,recurrence:e.recurrence,reminders:e.reminders}};
}

/** Source failures are isolated and last complete ranges survive provider failures. */
export async function calendarRange(client: SupabaseClient, userID: string, from:string,to:string,force=false) {
 // Date-only events belong to a calendar date even when the viewer is travelling.
 // Fetch a boundary cushion; each client displays events against its visible dates.
 from=new Date(Date.parse(from)-86400000).toISOString();
 to=new Date(Date.parse(to)+86400000).toISOString();
 const connections=(await connectionsFor(userID)).filter(c=>canReadEvents(c.scopes));
 const sources:Record<string,any>[]=[],coverage:Record<string,any>[]=[];
 for(let offset=0;;offset+=500) {
  const {data,error}=await client.from("calendar_sources").select("*").order("connection_id").order("calendar_id").range(offset,offset+499);
  if(error) throw error;sources.push(...(data || []));if(!data || data.length<500) break;
 }
 for(let offset=0;;offset+=500) {
  const {data,error}=await client.from("calendar_ranges").select("connection_id,calendar_id,refreshed_at").lte("starts_at",from).gte("ends_at",to).order("connection_id").order("calendar_id").order("starts_at").order("ends_at").range(offset,offset+499);
  if(error) throw error;coverage.push(...(data || []));if(!data || data.length<500) break;
 }
 const {pending,failures}=await queueCalendarRanges(userID,connections,sources as {connection_id:string;calendar_id:string;selected:boolean}[],coverage as {connection_id:string;calendar_id:string;refreshed_at:string}[],from,to,force);
 const selected=new Set((sources || []).filter(s=>s.selected).map(s=>`${s.connection_id}|${s.calendar_id}`));
 const events:WorkspaceEvent[]=[];
 // Supabase caps a page, not the complete period. Exhaust every page before reporting complete.
 for(let offset=0;;offset+=500) {
  const {data,error}=await client.from("calendar_events").select("*").gt("ends_at",from).lt("starts_at",to).order("starts_at").order("connection_id").order("calendar_id").order("id").range(offset,offset+499);
  if(error) throw error;
  for(const e of data || []) if(selected.has(`${e.connection_id}|${e.calendar_id}`)) events.push({...e,stable_id:eventIdentity(e.connection_id,e.calendar_id,e.id)});
  if(!data || data.length<500) break;
 }
 return {events:await calendarContext(client,events),calendars:sources.map(s=>({...s,can_write:s.can_write&&connections.some(c=>c.id===s.connection_id&&c.scopes.includes("https://www.googleapis.com/auth/calendar.events"))})),connections,from,to,pending,complete:pending===0&&failures.length===0,failures};
}
export const eventInput=z.object({
 connection_id:z.uuid(),calendar_id:z.string().min(1).max(1024),id:z.string().max(1024).optional(),
 etag:z.string().max(1024).optional(),title:z.string().trim().min(1).max(500),
 start:z.string().max(100),end:z.string().max(100),all_day:z.boolean().default(false),
 time_zone:z.string().max(100),description:z.string().max(20000).default(""),location:z.string().max(2000).default(""),
 reminders:z.object({useDefault:z.boolean(),overrides:z.array(z.object({method:z.enum(["popup","email"]),minutes:z.number().int().min(0).max(40320)})).max(5).optional()}).optional(),
 attendees:z.array(z.email()).max(100).default([]),recurrence:z.array(z.string().max(500)).max(5).optional(),
}).superRefine((v,ctx)=>{
 const valid=v.all_day ? z.iso.date().safeParse(v.start).success&&z.iso.date().safeParse(v.end).success : Number.isFinite(Date.parse(v.start))&&Number.isFinite(Date.parse(v.end));
 if(!valid || Date.parse(v.end)<=Date.parse(v.start)) ctx.addIssue({code:"custom",message:"Choose an end after the start."});
 try {new Intl.DateTimeFormat("en",{timeZone:v.time_zone});} catch {ctx.addIssue({code:"custom",message:"Choose a recognised time zone."});}
});
export async function ownCalendar(userID:string,connectionID:string,calendarID:string,write=false) {
 const connection=(await connectionsFor(userID)).find(c=>c.id===connectionID);
 if(!connection) throw new HttpError(404,"Calendar account not found.");
 const {data,error}=await adminClient().from("calendar_sources").select("*").eq("user_id",userID).eq("connection_id",connectionID).eq("calendar_id",calendarID).maybeSingle();
 if(error) throw error;
 if(!data || write && (!data.can_write || !connection.scopes.includes("https://www.googleapis.com/auth/calendar.events"))) throw new HttpError(403,"Allow calendar editing in Connections, and choose a writable calendar.");
 return {connection,source:data,api:google(await accessToken(connection))};
}
