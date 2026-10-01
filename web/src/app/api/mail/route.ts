import { z } from "zod";
import { requireEditor,failure,HttpError,limitedJSON } from "@/lib/http";
import { connectionsFor } from "@/lib/calendar";
import { adminClient } from "@/lib/supabase/server";
import { canMail,composeSchema,composeMIME,readMessage } from "@/lib/mail/model";
import { ownMailbox,draftRevision } from "@/lib/mail/gmail";
import { queueMail,dispatchOutbox } from "@/lib/mail/outbox";
export const maxDuration=60;
const headers={"Cache-Control":"private, no-store"};
const identifier=z.string().min(1).max(1024);
export async function GET(request:Request) {
 try {
  const {client,user}=await requireEditor(request),p=new URL(request.url).searchParams,accountID=p.get("account");
  if(p.get("operation")) {
   const {data,error}=await client.from("mail_outbox").select("id,status").eq("id",z.uuid().parse(p.get("operation"))).maybeSingle();if(error) throw error;
   return Response.json({operation:data},{headers});
  }
  if(!accountID) {
   const connected=(await connectionsFor(user.id)).filter(c=>canMail(c.scopes));
   const {data:preferences,error:preferencesError}=await client.from("mail_preferences").select("connection_id,signature");if(preferencesError) throw preferencesError;
   const accounts=connected.map(account=>({...account,signature:preferences?.find(p=>p.connection_id===account.id)?.signature || ""}));
   const {data:outbox,error}=await client.from("mail_outbox").select("id,connection_id,subject,status,due_at,error,created_at").order("created_at",{ascending:false}).limit(100);
   if(error) throw error;
   return Response.json({accounts,outbox:outbox || []},{headers});
  }
  const {api}=await ownMailbox(user.id,z.uuid().parse(accountID));
  if(p.get("attachment")) {
   const attachment=await api.attachment(identifier.parse(p.get("message")),identifier.parse(p.get("attachment")));
   if(attachment.size>25000000) throw new HttpError(413,"This attachment is too large to download here.");
   const filename=(p.get("filename") || "attachment").replace(/[\r\n"\\/]/g,"_").slice(0,255);
   return new Response(Buffer.from(attachment.data,"base64url"),{headers:{...headers,"Content-Type":"application/octet-stream","Content-Disposition":`attachment; filename*=UTF-8''${encodeURIComponent(filename)}`,"X-Content-Type-Options":"nosniff"}});
  }
  if(p.get("thread")) return Response.json({messages:await api.thread(identifier.parse(p.get("thread")))},{headers});
  if(p.get("forward")) {
   const message=readMessage(await api.message(identifier.parse(p.get("forward"))));
   if(message.attachments.reduce((sum,a)=>sum+a.size,0)>18000000) throw new HttpError(413,"Forward this large message in Gmail. Its attachments exceed the 18 MB composer limit.");
   const attachments=await Promise.all(message.attachments.map(async a=>({...a,data:a.data || Buffer.from((await api.attachment(message.id,a.id)).data,"base64url").toString("base64")})));
   return Response.json({message,attachments},{headers});
  }
  if(p.get("draft")) {
   const draft=await api.getDraft(identifier.parse(p.get("draft"))),message=readMessage(draft.message);
   if(message.attachments.reduce((sum,a)=>sum+a.size,0)>18000000) throw new HttpError(413,"Continue this large draft in Gmail. Its attachments exceed the 18 MB composer limit.");
   const attachments=await Promise.all(message.attachments.map(async a=>({...a,data:a.data || Buffer.from((await api.attachment(message.id,a.id)).data,"base64url").toString("base64")})));
   return Response.json({id:draft.id,revision:draftRevision(draft.message.payload),message,attachments},{headers});
  }
  if(p.has("drafts")) return Response.json(await api.drafts(p.get("page") || undefined),{headers});
  if(p.has("labels")) return Response.json(await api.labels(),{headers});
  const query=z.string().max(2000).parse(p.get("q") || "in:inbox");
  return Response.json(await api.list(query,p.get("page") || undefined),{headers});
 } catch(e) {return failure(e instanceof z.ZodError?new HttpError(400,e.issues[0].message):e);}
}
export async function POST(request:Request) {
 try {
  const {user}=await requireEditor(request),body=await limitedJSON(request,30000000,"This message is too large.");
  if(body.action==="preferences") {
   const account=z.uuid().parse(body.account),signature=z.string().max(5000).parse(body.signature);
   if(!(await connectionsFor(user.id)).some(c=>c.id===account&&canMail(c.scopes))) throw new HttpError(404,"Gmail account not found.");
   const {error}=await adminClient().from("mail_preferences").upsert({connection_id:account,user_id:user.id,signature},{onConflict:"connection_id"});if(error) throw error;
   return Response.json({saved:true},{headers});
  }
  if(body.action==="dispatch") return Response.json(await dispatchOutbox(user.id),{headers});
  if(body.action==="retry") {
   const id=z.uuid().parse(body.id),{data,error}=await adminClient().from("mail_outbox").update({status:"queued",error:null,due_at:new Date(Date.now()+10000).toISOString(),updated_at:new Date().toISOString()}).eq("id",id).eq("user_id",user.id).eq("status","failed").select("id");
   if(error) throw error;if(!data?.length) throw new HttpError(409,"Only a confirmed failed send can be retried. Check Sent for uncertain deliveries.");
   return Response.json({queued:true},{headers});
  }
  if(body.action==="cancel") {
   const id=z.uuid().parse(body.id),{data,error}=await adminClient().from("mail_outbox").update({status:"cancelled",raw_message:"",updated_at:new Date().toISOString()}).eq("id",id).eq("user_id",user.id).eq("status","queued").select("id");
   if(error) throw error;
   if(!data?.length) {
    const db=adminClient();
    // Reserve a cancellation even when a send acknowledgement was lost. The UUID
    // tombstone prevents a delayed or retried queue request from creating a send.
    if(body.account) {
     const account=z.uuid().parse(body.account);
     if(!(await connectionsFor(user.id)).some(c=>c.id===account && canMail(c.scopes))) throw new HttpError(404,"This Gmail account is no longer connected.");
     const {error:reserve}=await db.from("mail_outbox").upsert({id,user_id:user.id,connection_id:account,status:"cancelled",raw_message:""},{onConflict:"id",ignoreDuplicates:true});
     if(reserve) throw reserve;
     const {error:cancel}=await db.from("mail_outbox").update({status:"cancelled",raw_message:"",updated_at:new Date().toISOString()}).eq("id",id).eq("user_id",user.id).eq("status","queued");
     if(cancel) throw cancel;
    }
    const {data:current,error:lookup}=await db.from("mail_outbox").select("status").eq("id",id).eq("user_id",user.id).maybeSingle();
    if(lookup) throw lookup;
    if(current?.status!=="cancelled") throw new HttpError(409,"This message has already started sending. Check its status.");
   }
   return Response.json({cancelled:true},{headers});
  }
  if(body.action==="draft" || body.action==="send") {
   const parsed=composeSchema.safeParse(body.message);if(!parsed.success) throw new HttpError(400,parsed.error.issues[0].message);
   const v=parsed.data;
   if(body.action==="send") return Response.json(await queueMail(user.id,z.uuid().parse(body.operation_id),v,body.due_at?z.iso.datetime().parse(body.due_at):undefined),{headers});
   const {account,api}=await ownMailbox(user.id,v.connection_id);
   if(!account.email) throw new HttpError(409,"Reconnect this sender.");
   if(v.id) {
    if(!v.revision) throw new HttpError(409,"Open this draft again before editing it.");
    const current=await api.getDraft(v.id);
    if(draftRevision(current.message.payload)!==v.revision) throw new HttpError(409,"This draft changed in Gmail. Your edits are saved on this device. Close and reopen the Gmail draft before continuing.");
   }
   const draft=await api.draft(v.id,await composeMIME(v,account.email),v.thread_id);
   const saved=await api.getDraft(draft.id);
   return Response.json({id:draft.id,revision:draftRevision(saved.message.payload)},{headers});
  }
  const v=z.object({account:z.uuid(),id:identifier,action:z.enum(["archive","read","unread","star","unstar","trash","restore","spam","not_spam","label","delete_draft"]),label:identifier.optional()}).parse(body),{api}=await ownMailbox(user.id,v.account);
  if(v.action==="delete_draft") return Response.json(await api.deleteDraft(v.id),{headers});
  const changes:Record<string,[string[],string[]]>={archive:[[],["INBOX"]],read:[[],["UNREAD"]],unread:[["UNREAD"],[]],star:[["STARRED"],[]],unstar:[[],["STARRED"]],trash:[["TRASH"],["INBOX"]],restore:[["INBOX"],["TRASH"]],spam:[["SPAM"],["INBOX"]],not_spam:[["INBOX"],["SPAM"]],label:[[v.label || ""],[]]};
  const [add,remove]=changes[v.action];if(add.includes("")) throw new HttpError(400,"Choose a label.");
  return Response.json(await api.modify(v.id,add,remove),{headers});
 } catch(e) {return failure(e instanceof z.ZodError?new HttpError(400,e.issues[0].message):e);}
}
