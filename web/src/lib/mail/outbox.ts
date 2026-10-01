import { adminClient } from "../supabase/server";
import { encryptToken,decryptToken } from "../calendar";
import { HttpError } from "../http";
import { ownMailbox,draftRevision } from "./gmail";
import { composeMIME,type Compose } from "./model";
export async function queueMail(userID:string,id:string,v:Compose,due?:string) {
 if(!v.to.length && !v.cc.length && !v.bcc.length) throw new HttpError(400,"Add at least one recipient.");
 const {account,api}=await ownMailbox(userID,v.connection_id);
 if(!account.email) throw new HttpError(409,"Reconnect to confirm this account’s sender address.");
 const db=adminClient(),{data:existing,error:lookup}=await db.from("mail_outbox").select("id,status,due_at,connection_id").eq("user_id",userID).eq("id",id).maybeSingle();
 if(lookup) throw lookup;
 if(existing) {if(existing.connection_id!==v.connection_id) throw new HttpError(409,"This send request belongs to another account.");return existing;}
 const dueAt=new Date(Math.max(Date.now()+10000,due?Date.parse(due):0));
 if(!Number.isFinite(dueAt.getTime()) || dueAt.getTime()>Date.now()+366*86400000) throw new HttpError(400,"Choose a send time within the next year.");
 if(v.id) {if(!v.revision || draftRevision((await api.getDraft(v.id)).message.payload)!==v.revision) throw new HttpError(409,"This draft changed in Gmail. Reopen it before sending. Your local edits are preserved.");}
 const {data:allowed,error:limitError}=await db.rpc("hit_booking_rate_limit",{p_bucket:`mail-send:${userID}`,p_limit:20,p_window_seconds:60});
 if(limitError) throw limitError;if(!allowed) throw new HttpError(429,"Too many send requests. Try again in a minute.");
 const raw=await composeMIME(v,account.email,id);
 const {data,error}=await db.from("mail_outbox").insert({id,user_id:userID,connection_id:v.connection_id,draft_id:v.id || null,thread_id:v.thread_id || null,raw_message:encryptToken(raw),subject:v.subject,due_at:dueAt.toISOString()}).select("id,status,due_at").single();
 if(error) {
  if(error.code==="23505") {const {data:retry}=await db.from("mail_outbox").select("id,status,due_at").eq("id",id).eq("user_id",userID).single();if(retry) return retry;}
  throw error;
 }
 return data;
}
export async function dispatchOutbox(userID?:string) {
 const db=adminClient(),stamp=()=>new Date().toISOString();
 // A crashed worker cannot safely retry an email that may already have been accepted.
 let abandoned=db.from("mail_outbox").update({status:"uncertain",error:"Delivery was interrupted. Check Sent mail before sending again.",updated_at:stamp()}).eq("status","sending").lt("updated_at",new Date(Date.now()-180000).toISOString());
 if(userID) abandoned=abandoned.eq("user_id",userID);
 const {error:abandonedError}=await abandoned;if(abandonedError) throw abandonedError;
 // Reconciliation searches Sent by the deterministic RFC message ID. A missing result
 // is never proof of failure, so uncertainty never triggers an automatic resend.
 let uncertain=db.from("mail_outbox").select("id,user_id,connection_id,draft_id").eq("status","uncertain").order("updated_at").limit(5);
 if(userID) uncertain=uncertain.eq("user_id",userID);
 const {data:pending,error:pendingError}=await uncertain;if(pendingError) throw pendingError;
 for(const item of pending || []) {
  try {
   const {api}=await ownMailbox(item.user_id,item.connection_id);
   const found=await api.call<{messages?:{id:string}[]}>(`messages?${new URLSearchParams({q:`in:sent rfc822msgid:${item.id}@voice-notes.local`,maxResults:"2"})}`);
   const sent=found.messages?.[0];
   const {error}=await db.from("mail_outbox").update(sent?{status:"sent",provider_id:sent.id,raw_message:"",error:null,updated_at:stamp()}:{updated_at:stamp()}).eq("id",item.id).eq("status","uncertain");
   if(error) throw error;
   if(sent && item.draft_id) await api.deleteDraft(item.draft_id).catch(()=>{});
  } catch { /* Access errors preserve the original uncertain result for recovery. */ }
 }
 let query=db.from("mail_outbox").select("id,user_id,connection_id,draft_id,thread_id,raw_message").eq("status","queued").lte("due_at",stamp()).order("due_at").limit(5);
 if(userID) query=query.eq("user_id",userID);
 const {data:due,error}=await query;if(error) throw error;
 for(const item of due || []) {
  let api:Awaited<ReturnType<typeof ownMailbox>>["api"];
  try {api=(await ownMailbox(item.user_id,item.connection_id)).api;} catch(e) {
   await db.from("mail_outbox").update({status:"failed",error:e instanceof Error?e.message:"Reconnect this account before sending.",updated_at:stamp()}).eq("id",item.id).eq("status","queued");continue;
  }
  const {data:claimed,error:claimError}=await db.from("mail_outbox").update({status:"sending",updated_at:stamp()}).eq("id",item.id).eq("status","queued").select("id").maybeSingle();
  if(claimError) throw claimError;if(!claimed) continue;
  let sent:{id:string};
  try {
   sent=await api.call<{id:string}>("messages/send","POST",{raw:decryptToken(item.raw_message),...(item.thread_id?{threadId:item.thread_id}:{})});
  } catch(e) {
   const definite=e instanceof HttpError && [400,401,403,404,429].includes(e.status);
   await db.from("mail_outbox").update({status:definite?"failed":"uncertain",error:definite?(e as Error).message:"The delivery result is uncertain. Check Sent mail before sending again.",updated_at:stamp()}).eq("id",item.id);continue;
  }
  const {error:recordError}=await db.from("mail_outbox").update({status:"sent",provider_id:sent.id,raw_message:"",updated_at:stamp()}).eq("id",item.id);
  if(recordError) throw recordError; // Remains Sending; later reconciliation marks uncertainty, never resends.
  if(item.draft_id) await api.deleteDraft(item.draft_id).catch(()=>{});
 }
 return {processed:due?.length || 0};
}
