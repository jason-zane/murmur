import type {SupabaseClient} from "@supabase/supabase-js";
import type {CalendarMeeting} from "./documents";

/** Resolve old note links only when the provider ID is unique across the owner's cache. */
export async function calendarContext<T extends CalendarMeeting>(client:SupabaseClient,events:T[]) {
 const ids=[...new Set(events.map(e=>e.id))],copies=new Map<string,Set<string>>(),bookings:Record<string,any>[]=[];
 for(let i=0;i<ids.length;i+=100) {
  for(let offset=0;;offset+=500) {
   const {data,error}=await client.from("calendar_events").select("id,connection_id,calendar_id").in("id",ids.slice(i,i+100)).order("connection_id").order("calendar_id").order("id").range(offset,offset+499);
   if(error) throw error;for(const row of data || []) {const keys=copies.get(row.id) || new Set<string>();keys.add(`${row.connection_id}|${row.calendar_id}`);copies.set(row.id,keys);}if(!data || data.length<500) break;
  }
  for(let offset=0;;offset+=500) {
   const {data,error}=await client.from("bookings").select("id,connection_id,calendar_id,provider_event_id,title,summary_template,guest_name,guest_email,answers,event_types(title)").eq("status","confirmed").in("provider_event_id",ids.slice(i,i+100)).order("id").range(offset,offset+499);
   if(error) throw error;bookings.push(...(data || []));if(!data || data.length<500) break;
  }
 }
 return events.map(event=>{
  const unique=copies.get(event.id)?.size===1;
  const candidates=bookings.filter(b=>b.provider_event_id===event.id);
  const b=candidates.find(b=>b.connection_id===event.connection_id&&b.calendar_id===event.calendar_id) || (unique&&candidates.length===1&&!candidates[0].connection_id?candidates[0]:null);
  return {...event,legacy_id_unique:unique,...(b?{booking:{id:b.id,event_type:b.event_types?.title || b.title,template:b.summary_template || "Meeting",guest_name:b.guest_name,guest_email:b.guest_email,answers:b.answers || []}}:{})};
 });
}
