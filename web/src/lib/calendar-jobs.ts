import {createHash,randomUUID} from "node:crypto";
import {adminClient} from "./supabase/server";
import {connectionsFor,accessToken,syncSources} from "./calendar";
import {google,canListCalendars,GoogleError,type GoogleCalendar} from "./google";
const stamp=()=>new Date().toISOString();
export const rangeJobKey=(account:string,calendar:string,from:string,to:string)=>createHash("sha256").update(JSON.stringify([account,calendar,new Date(from).toISOString(),new Date(to).toISOString()])).digest("hex");

/** One requested range is one durable job. Duplicate clients share the same checkpoint. */
export async function queueCalendarRanges(userID:string,connections:{id:string}[],sources:{connection_id:string;calendar_id:string;selected:boolean}[],coverage:{connection_id:string;calendar_id:string;refreshed_at:string}[],from:string,to:string,force=false) {
 const db=adminClient(),fresh=new Set(coverage.filter(c=>Date.now()-Date.parse(c.refreshed_at)<300000).map(c=>`${c.connection_id}|${c.calendar_id}`));
 const ranges=sources.filter(s=>s.selected&&(force||!fresh.has(`${s.connection_id}|${s.calendar_id}`))).map(s=>({job_key:rangeJobKey(s.connection_id,s.calendar_id,from,to),user_id:userID,connection_id:s.connection_id,calendar_id:s.calendar_id,kind:"range",starts_at:from,ends_at:to}));
 const discovery=connections.map(c=>({job_key:`discover:${c.id}:${stamp().slice(0,10)}`,user_id:userID,connection_id:c.id,calendar_id:null,starts_at:null,ends_at:null,kind:"discover"}));
 for(let i=0;i<ranges.length+discovery.length;i+=100) {
  const {error}=await db.from("calendar_jobs").upsert([...ranges,...discovery].slice(i,i+100),{onConflict:"job_key",ignoreDuplicates:true});if(error) throw error;
 }
 for(let i=0;i<ranges.length;i+=100) {
  const {error}=await db.from("calendar_jobs").update({status:"queued",staged:{},page_token:null,retry_after:stamp(),updated_at:stamp(),error:null}).in("job_key",ranges.slice(i,i+100).map(r=>r.job_key)).eq("status","complete");if(error) throw error;
 }
 const keys=[...ranges,...discovery].map(j=>j.job_key),jobs:Record<string,any>[]=[];
 for(let i=0;i<keys.length;i+=100) {const {data,error}=await db.from("calendar_jobs").select("connection_id,calendar_id,status,error").eq("user_id",userID).in("job_key",keys.slice(i,i+100));if(error) throw error;jobs.push(...(data || []));}
 return {pending:jobs.filter(j=>j.status!=="complete").length,failures:jobs.filter(j=>j.status==="failed").map(j=>({connection_id:j.connection_id,calendar_id:j.calendar_id,message:j.error || "Calendar could not update. Reconnect in Connections."}))};
}

/** A page is checkpointed before fetching another. Only a completed job can replace coverage. */
export async function runCalendarJobs(userID?:string) {
 const db=adminClient(),deadline=Date.now()+40000;
 let abandoned=db.from("calendar_jobs").update({status:"queued",lease:null,retry_after:stamp()}).eq("status","running").lt("updated_at",new Date(Date.now()-180000).toISOString());
 if(userID) abandoned=abandoned.eq("user_id",userID);
 const {error:abandonedError}=await abandoned;if(abandonedError) throw abandonedError;
 let processed=0;
 while(Date.now()<deadline&&processed<3) {
  let due=db.from("calendar_jobs").select("*").in("status",["queued","failed"]).lte("retry_after",stamp()).order("retry_after").limit(1);
  if(userID) due=due.eq("user_id",userID);
  const {data,error}=await due;if(error) throw error;const job=data?.[0];if(!job) break;
  if(job.dirty) { job.staged={};job.page_token=null; }
  const lease=randomUUID(),{data:claimed,error:claimError}=await db.from("calendar_jobs").update({status:"running",lease,dirty:false,...(job.dirty?{staged:{},page_token:null}:{}),attempts:job.attempts+1,updated_at:stamp()}).eq("id",job.id).eq("status",job.status).eq("dirty",job.dirty ?? false).eq("retry_after",job.retry_after).select("id").maybeSingle();
  if(claimError) throw claimError;if(!claimed) continue;processed++;
  try {
   const account=(await connectionsFor(job.user_id)).find(c=>c.id===job.connection_id);
   if(!account) throw new Error("This calendar account was disconnected.");
   const api=google(await accessToken(account));
   if(job.kind==="discover") {
    const page=canListCalendars(account.scopes)?await api.calendarsPage(job.page_token || undefined):{items:[{id:"primary",summary:account.email || "Primary calendar",primary:true,accessRole:"owner"} as GoogleCalendar],nextPageToken:undefined};
    const staged={...job.staged,...Object.fromEntries((page.items || []).map(c=>[c.id,c]))};
    if(!page.nextPageToken) await syncSources(account,Object.values(staged) as GoogleCalendar[]);
    const {error}=await db.from("calendar_jobs").update({status:page.nextPageToken?"queued":"complete",staged:page.nextPageToken?staged:{},page_token:page.nextPageToken || null,lease:null,error:null,retry_after:stamp(),updated_at:stamp()}).eq("id",job.id).eq("lease",lease);if(error) throw error;
   } else {
    const {data:source,error:sourceError}=await db.from("calendar_sources").select("time_zone").eq("connection_id",job.connection_id).eq("calendar_id",job.calendar_id).single();if(sourceError) throw sourceError;
    const page=await api.eventsPage(job.calendar_id,new Date(job.starts_at),new Date(job.ends_at),job.page_token || undefined),{workspaceEvent}=await import("./calendar-workspace");
    const events=(page.items || []).map(e=>workspaceEvent(e,job.connection_id,job.calendar_id,source.time_zone || "UTC")).filter(e=>e!==null);
    const staged={...job.staged,...Object.fromEntries(events.map(e=>[e.id,e]))};
    if(page.nextPageToken) {
     const {error}=await db.from("calendar_jobs").update({status:"queued",staged,page_token:page.nextPageToken,lease:null,retry_after:stamp(),updated_at:stamp(),error:null}).eq("id",job.id).eq("lease",lease);if(error) throw error;
    } else {const {error}=await db.rpc("commit_calendar_job",{p_id:job.id,p_lease:lease,p_events:Object.values(staged)});if(error) throw error;}
   }
  } catch(e) {
   const {error}=await db.from("calendar_jobs").update({status:"failed",lease:null,...(e instanceof GoogleError&&[400,410].includes(e.status)?{page_token:null,staged:{}}:{}),error:e instanceof Error?e.message:"Calendar could not update.",retry_after:new Date(Date.now()+Math.min(3600000,30000*2**Math.min(job.attempts,6))).toISOString(),updated_at:stamp()}).eq("id",job.id).eq("lease",lease);if(error) throw error;
  }
 }
 return {processed};
}
