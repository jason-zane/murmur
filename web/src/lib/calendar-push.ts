import {randomBytes,randomUUID,timingSafeEqual} from "node:crypto";
import {z} from "zod";
import {adminClient} from "./supabase/server";
import {connectionsFor,accessToken} from "./calendar";
import {google,canReadEvents} from "./google";
import {siteURL} from "./config";

export type CalendarChannel={id:string;token:string;resource_id:string|null;expires_at:string};
export function validCalendarNotification(headers:Headers,channel:CalendarChannel,now=Date.now()) {
 const token=Buffer.from(headers.get("x-goog-channel-token") || ""),expected=Buffer.from(channel.token);
 const resource=headers.get("x-goog-resource-id"),state=headers.get("x-goog-resource-state");
 return headers.get("x-goog-channel-id")===channel.id && token.length===expected.length && timingSafeEqual(token,expected)
  && Boolean(resource) && (!channel.resource_id || resource===channel.resource_id)
  && ["sync","exists","not_exists"].includes(state || "") && Date.parse(channel.expires_at)>now;
}

/** Register before calling Google: its initial sync notification may arrive first. */
export async function renewCalendarChannels(userID?:string) {
 if(!siteURL().startsWith("https://")) return {renewed:0};
 const db=adminClient(),now=new Date().toISOString(),deadline=Date.now()+25000;
 let renewed=0;
 while(renewed<2&&Date.now()<deadline) {
  const id=randomUUID(),token=randomBytes(32).toString("hex"),expires=Date.now()+7*86400000;
  const {data,error}=await db.rpc("claim_calendar_channel",{p_owner:userID || null,p_id:id,p_token:token});if(error) throw error;
  const source=data?.[0];if(!source) break;renewed++;
  try {
   const account=(await connectionsFor(source.user_id)).find(c=>c.id===source.connection_id);
   if(!account || !canReadEvents(account.scopes)) throw new Error("Reconnect this calendar account.");
   const result=await google(await accessToken(account)).watchEvents(source.calendar_id,id,siteURL()+"/api/calendar/notifications",token,expires);
   if(!result || result.id!==id || !result.resourceId || !Number.isFinite(Number(result.expiration))) throw new Error("Google returned an incomplete notification channel.");
   const {error}=await db.from("calendar_push_channels").update({resource_id:result.resourceId,expires_at:new Date(Number(result.expiration)).toISOString(),error:null}).eq("id",id);if(error) throw error;
  } catch(e) {
   const {error}=await db.from("calendar_push_channels").update({expires_at:now,retry_after:new Date(Date.now()+600000).toISOString(),error:e instanceof Error?e.message:"Calendar notifications could not renew."}).eq("id",id);if(error) throw error;
  }
 }
 return {renewed};

}

export async function acceptCalendarNotification(headers:Headers) {
 const id=headers.get("x-goog-channel-id");if(!z.uuid().safeParse(id).success) return null;
 const db=adminClient(),{data:channel,error}=await db.from("calendar_push_channels").select("*").eq("id",id!).maybeSingle();if(error) throw error;
 if(!channel || !validCalendarNotification(headers,channel)) return null;
 if(headers.get("x-goog-resource-state")==="sync") return channel.user_id as string;
 const scope=()=>db.from("calendar_jobs").update({dirty:true}).eq("connection_id",channel.connection_id).eq("calendar_id",channel.calendar_id).eq("kind","range");
 // A running job keeps its lease; commit schedules a second pass when dirty.
 const {error:mark}=await scope();if(mark) throw mark;
 const {error:queue}=await db.from("calendar_jobs").update({status:"queued",retry_after:new Date().toISOString(),staged:{},page_token:null,error:null}).eq("connection_id",channel.connection_id).eq("calendar_id",channel.calendar_id).eq("kind","range").in("status",["complete","failed"]);if(queue) throw queue;
 return channel.user_id as string;
}
