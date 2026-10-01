"use client";
import { useState } from "react";
import {calendarInstant,calendarWallTime} from "@/lib/calendar-time";
import { Dialog } from "./dialog";
import type { WorkspaceEvent } from "@/lib/calendar-workspace";
type Source={connection_id:string;calendar_id:string;name:string;can_write?:boolean};
const local=(date:Date)=>new Date(date.getTime()-date.getTimezoneOffset()*60000).toISOString().slice(0,16);
export function CalendarEditor({event,date,endDate,allDayDefault,calendars,onClose,onSaved}:{event?:WorkspaceEvent;date:Date;endDate?:Date;allDayDefault?:boolean;calendars:Source[];onClose:()=>void;onSaved:()=>void}) {
 const initialZone=event?.details?.time_zone || Intl.DateTimeFormat().resolvedOptions().timeZone;
 const [timeZone,setTimeZone]=useState(initialZone),[reminder,setReminder]=useState(event?"keep":"default");
 const zoned=(date:Date)=>calendarWallTime(date.toISOString(),initialZone);
 const [title,setTitle]=useState(event?.title || ""),[source,setSource]=useState(event?`${event.connection_id}|${event.calendar_id}`:calendars.find(c=>c.can_write)?`${calendars.find(c=>c.can_write)!.connection_id}|${calendars.find(c=>c.can_write)!.calendar_id}`:""),
 [allDay,setAllDay]=useState(event?.details?.all_day || allDayDefault || false),[start,setStart]=useState(event?.details?.all_day?event.details.start_date!:(allDayDefault?local(date).slice(0,10):zoned(event?new Date(event.starts_at):date))),[end,setEnd]=useState(event?.details?.all_day?event.details.end_date!:(allDayDefault?local(endDate || new Date(date.getTime()+86400000)).slice(0,10):zoned(event?new Date(event.ends_at):endDate || new Date(date.getTime()+3600000)))),
 [description,setDescription]=useState(event?.details?.description || ""),[location,setLocation]=useState(event?.details?.location || ""),[guests,setGuests]=useState(event?.attendees.map(a=>a.email).filter(Boolean).join(", ") || ""),[repeat,setRepeat]=useState(""),[error,setError]=useState(""),[busy,setBusy]=useState(false);
 async function remove() {
  if(!event || !confirm("Remove this event? Google notifies guests if you organise it. This occurrence only is removed for repeating events.")) return;
  setBusy(true);setError("");try {const r=await fetch("/api/calendar/events",{method:"DELETE",headers:{"Content-Type":"application/json"},body:JSON.stringify({connection_id:event.connection_id,calendar_id:event.calendar_id,id:event.id,etag:event.details.etag})});const b=await r.json();if(!r.ok) throw new Error(b.error);onSaved();}catch(e){setError((e as Error).message);}finally{setBusy(false);}
 }
 async function save() {
  setBusy(true);setError("");
  try {
   const split=source.indexOf("|"),connection_id=source.slice(0,split),calendar_id=source.slice(split+1);
   const instant=(value:string,original?:string)=>calendarInstant(value,timeZone,original,initialZone);
   const reminders=reminder==="keep"?undefined:reminder==="default"?{useDefault:true}:{useDefault:false,overrides:reminder==="none"?[]:[{method:"popup",minutes:Number(reminder)}]};
   const r=await fetch("/api/calendar/events",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({connection_id,calendar_id,id:event?.id,etag:event?.details?.etag,title,start:allDay?start:instant(start,event?.starts_at),end:allDay?end:instant(end,event?.ends_at),all_day:allDay,time_zone:timeZone,reminders,description,location,attendees:guests.split(/[,;]/).map(v=>v.trim()).filter(Boolean),...(!event && repeat?{recurrence:[`RRULE:FREQ=${repeat}`]}:{})})});
   const b=await r.json();if(!r.ok) throw new Error(b.error);onSaved();
  } catch(e) {setError(e instanceof Error?e.message:"Could not save this event.");} finally {setBusy(false);}
 }
 return <Dialog label={event?"Edit event":"New event"} onClose={()=>{if(!busy)onClose();}}><form onSubmit={e=>{e.preventDefault();void save();}}>
  <div className="heading-row"><h2>{event?"Edit event":"New event"}</h2><button type="button" className="text-link" disabled={busy} onClick={onClose}>Cancel</button></div>
  {event?.details?.recurring_id && <p className="notice">Changes apply to this occurrence.</p>}
  {error && <p className="notice" role="alert">{error}</p>}
  <label className="field"><span>Title</span><input autoFocus required value={title} onChange={e=>setTitle(e.target.value)} /></label>
  <label className="field"><span>Calendar</span><select required disabled={Boolean(event)} value={source} onChange={e=>setSource(e.target.value)}><option value="">Choose a calendar</option>{calendars.filter(c=>c.can_write).map(c=><option key={`${c.connection_id}|${c.calendar_id}`} value={`${c.connection_id}|${c.calendar_id}`}>{c.name}</option>)}</select></label>
  <label className="check"><input type="checkbox" checked={allDay} onChange={e=>{setAllDay(e.target.checked);setStart(e.target.checked?start.slice(0,10):start+"T09:00");const endDay=end.slice(0,10);const following=new Date(`${start.slice(0,10)}T12:00:00`);following.setDate(following.getDate()+1);setEnd(e.target.checked?(endDay>start.slice(0,10)?endDay:local(following).slice(0,10)):end+"T10:00");}}/>All day</label>
  <div className="form-grid"><label className="field"><span>Starts</span><input required type={allDay?"date":"datetime-local"} value={start} onChange={e=>setStart(e.target.value)}/></label><label className="field"><span>{allDay?"Ends before":"Ends"}</span><input required type={allDay?"date":"datetime-local"} value={end} onChange={e=>setEnd(e.target.value)}/></label></div>
  {!allDay && <label className="field"><span>Time zone</span><input list="calendar-time-zones" required value={timeZone} onChange={e=>setTimeZone(e.target.value)}/><datalist id="calendar-time-zones">{Intl.supportedValuesOf("timeZone").map(zone=><option key={zone} value={zone}/>)}</datalist></label>}
  <p className="fine-print">Times in {timeZone}. All-day end dates are exclusive.</p>
  <label className="field"><span>Reminder</span><select value={reminder} onChange={e=>setReminder(e.target.value)}>{event&&<option value="keep">Keep existing reminders</option>}<option value="default">Calendar defaults</option><option value="none">No reminder</option><option value="0">At the start</option><option value="10">10 minutes before</option><option value="30">30 minutes before</option><option value="60">1 hour before</option><option value="1440">1 day before</option></select></label>
  {!event && <label className="field"><span>Repeat</span><select value={repeat} onChange={e=>setRepeat(e.target.value)}><option value="">Does not repeat</option><option value="DAILY">Daily</option><option value="WEEKLY">Weekly</option><option value="MONTHLY">Monthly</option></select></label>}
  <label className="field"><span>Guests</span><input value={guests} placeholder="Email addresses, separated by commas" onChange={e=>setGuests(e.target.value)}/></label>
  <label className="field"><span>Location</span><input value={location} onChange={e=>setLocation(e.target.value)}/></label>
  <label className="field"><span>Description</span><textarea rows={4} value={description} onChange={e=>setDescription(e.target.value)}/></label>
  <p className="fine-print">Google sends calendar invitations and updates to your guests.</p><button className="button primary" disabled={busy || !source}>{busy?"Saving…":"Save event"}</button>{event && <button type="button" className="text-link" disabled={busy} onClick={()=>void remove()}>Remove event…</button>}
 </form></Dialog>;
}
