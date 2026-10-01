import { z } from "zod";
import { isDeepStrictEqual } from "node:util";
import { adminClient } from "../supabase/server";
import { HttpError } from "../http";
import { connectionsFor } from "../calendar";
import { canMail, composeSchema, composeMIME, type Compose } from "./model";
import { ownMailbox, draftRevision } from "./gmail";

// Incomplete addresses must still be recoverable. Sending uses composeSchema instead.
export const editableDraftSchema = z.object({
 connection_id:z.uuid(),id:z.string().max(1024).optional(),revision:z.string().max(100).optional(),thread_id:z.string().max(1024).optional(),
 to:z.array(z.string().max(2000)).max(100),cc:z.array(z.string().max(2000)).max(100),bcc:z.array(z.string().max(2000)).max(100),
 scheduled_at:z.iso.datetime().optional(),
 subject:z.string().max(998),text:z.string().max(1000000),html:z.string().max(1000000).optional(),
 in_reply_to:z.string().max(2000).optional(),references:z.string().max(10000).optional(),
 attachments:z.array(z.object({name:z.string().min(1).max(255),type:z.string().max(100),cid:z.string().max(998).optional(),data:z.string().max(28000000).regex(/^[A-Za-z0-9+/]*={0,2}$/)})).max(20),
}).refine(v=>v.to.length+v.cc.length+v.bcc.length<=100).refine(v=>v.attachments.reduce((n,a)=>n+Buffer.from(a.data,"base64").length,0)<=18000000);
export const workspaceSaveSchema=z.object({workspace_id:z.uuid(),workspace_version:z.number().int().min(0),message:editableDraftSchema});
export type WorkspaceDraft={id:string;connection_id:string;document:Compose;version:number;gmail_state:string;gmail_error:string|null;updated_at:string};
class DraftChangedDuringSave extends HttpError {constructor(){super(409,"This Concourse draft changed during saving. Your device edits are kept; reopen it or keep them as a new draft.");}}
export async function saveWorkspaceDraft(userID:string,input:z.infer<typeof workspaceSaveSchema>) {
 const db=adminClient(),{workspace_id:id,workspace_version:expected}=input;
 let message=JSON.parse(JSON.stringify(input.message)) as Compose;
 if(!(await connectionsFor(userID)).some(c=>c.id===message.connection_id&&canMail(c.scopes)))throw new HttpError(403,"This sender is no longer connected. Your device copy is retained.");
 const lookup=()=>db.from("mail_drafts").select("*").eq("id",id).eq("user_id",userID).maybeSingle();
 const {data:current,error:readError}=await lookup();if(readError)throw readError;
 if(current&&current.connection_id!==message.connection_id)throw new HttpError(409,"Choose a separate draft for this sender.");
 if(current?.gmail_state==="pending"&&!isDeepStrictEqual(current.document,message))throw new HttpError(409,"A Gmail save is in progress. Your latest edits stay on this device; retry shortly.");
 const content=(v:Compose)=>({...v,id:undefined,revision:undefined});
 if(current?.document.id&&!message.id)message={...message,id:current.document.id,revision:current.document.revision};
 // Lost acknowledgements may be retried without replacing a newer document.
 let row:WorkspaceDraft;
 if(current&&isDeepStrictEqual(current.document,message))row=current;
 else {
  if((current?.version || 0)!==expected)throw new HttpError(409,"This Concourse draft changed in another session. Your device copy is kept; reopen the saved draft or keep your edits as a new draft.");
  const patch={document:message,gmail_state:current?.gmail_state==="uncertain"?"uncertain":"unsynced",version:expected+1,updated_at:new Date().toISOString()};
  const result=current?await db.from("mail_drafts").update(patch).eq("id",id).eq("user_id",userID).eq("version",expected).select("*").maybeSingle():await db.from("mail_drafts").insert({id,user_id:userID,connection_id:message.connection_id,...patch}).select("*").single();
  if(result.error?.code==="23505" || (!result.error&&!result.data))throw new HttpError(409,"This Concourse draft changed in another session. Your device copy is kept.");
  if(result.error)throw result.error;row=result.data;
 }
 if(row.gmail_state==="synced"&&isDeepStrictEqual(content(row.document),content(message)))return {workspace_id:id,workspace_version:row.version,id:row.document.id,revision:row.document.revision,concourse_saved:true,gmail_saved:true,gmail_error:null};
 const answer=(draft:WorkspaceDraft)=>({workspace_id:id,workspace_version:draft.version,id:draft.document.id,revision:draft.document.revision,concourse_saved:true,gmail_saved:draft.gmail_state==="synced",gmail_error:draft.gmail_error});
 if(row.gmail_state==="pending" || row.gmail_state==="uncertain")return {...answer(row),gmail_saved:false,gmail_error:"The last Gmail save is unconfirmed. Your Concourse draft is safe. Check Gmail before creating another copy."};
 let providerRequested=false;
 try {
  const parsed=composeSchema.safeParse(message);
  if(!parsed.success)throw new HttpError(400,"Saved in Concourse. Complete valid email addresses before this draft can sync to Gmail.");
  const v=parsed.data,{account,api}=await ownMailbox(userID,v.connection_id);
  if(!account.email)throw new HttpError(409,"Reconnect this sender in Connected apps.");
  if(v.id){const remote=await api.getDraft(v.id);if(!v.revision||draftRevision(remote.message.payload)!==v.revision)throw new HttpError(409,"This draft changed in Gmail. Your Concourse edits are safe. Reopen the Gmail draft or keep your edits as a new draft.");}
  const raw=await composeMIME(v,account.email);
  const claim=await db.from("mail_drafts").update({gmail_state:"pending",gmail_error:null}).eq("id",id).eq("user_id",userID).eq("version",row.version).in("gmail_state",["synced","error","unsynced"]).select("id").maybeSingle();
  if(claim.error)throw claim.error;if(!claim.data)throw new DraftChangedDuringSave();
  providerRequested=true;
  const remote=await api.draft(v.id,raw,v.thread_id);
  // Keep the provider ID even if the subsequent verification fails.
  let document:Compose={...message,id:remote.id,revision:undefined};
  const bindingSave=await db.from("mail_drafts").update({document}).eq("id",id).eq("user_id",userID).eq("version",row.version);if(bindingSave.error)throw bindingSave.error;
  const saved=await api.getDraft(remote.id);document={...message,id:remote.id,revision:draftRevision(saved.message.payload)};
  const final=await db.from("mail_drafts").update({document,gmail_state:"synced",gmail_error:null}).eq("id",id).eq("user_id",userID).eq("version",row.version).select("*").maybeSingle();
  if(final.error)throw final.error;if(!final.data)throw new DraftChangedDuringSave();
  return answer(final.data);
 } catch(error) {
  if(error instanceof DraftChangedDuringSave)throw error;
  const explanation=error instanceof Error?error.message:"Gmail could not save this draft.";
  // A request with no acknowledgement must never silently create a second provider draft.
  const state=providerRequested?"uncertain":"error";
  const result=await db.from("mail_drafts").update({gmail_state:state,gmail_error:explanation}).eq("id",id).eq("user_id",userID).eq("version",row.version).select("*").maybeSingle();
  if(result.error)throw result.error;if(!result.data)throw new DraftChangedDuringSave();
  return {...answer(result.data),gmail_saved:false,gmail_error:explanation};
 }
}
