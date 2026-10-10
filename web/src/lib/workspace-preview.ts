/** Synthetic, browser-local transports for design QA. No transport can fall back to a network request. */
import type { MailRequest } from "@/components/mail-workspace";
import {mailboxColours,mailboxIcons,type MailIdentity} from "./mail/identity";
import type { Compose, MailMessage } from "./mail/model";
import { documentSchema, type CloudSession, type MeetingDocument } from "./documents";
import { effectiveFollowUp,followUpWrite,type SavedFollowUp } from "./follow-up/drafts";
import { sampleNote } from "./follow-up/prototype";
const KEY="concourse:workspace-preview:v1";
const MAIL_DRAFT_KEY="concourse:mail-draft-server-fixture:v1";
const FOLLOW_UP_KEY="concourse:follow-up-server-fixture:v1";
type Storage=Pick<globalThis.Storage,"getItem"|"setItem">;
const initialAccounts=[{id:"sample-work",email:"sam@example.com",signature:"Sam"},{id:"sample-personal",email:"sam.personal@example.com",signature:"Sam"}];
function message(id:string,subject:string,from:string,text:string,date:string):MailMessage {
  return {id,thread_id:id,subject,from,to:"sam@example.com",cc:"",bcc:"",in_reply_to:"",reply_to:"",message_id:`<${id}@example.com>`,references:"",date,text,html:"",source_html:"",labels:["INBOX","UNREAD"],attachments:[]};
}
function initialNotes():CloudSession[] {
  return ["launch","support"].map((id,i)=>{
    const source=sampleNote(id,1),started=`2026-09-${30-i}T09:00:00.000Z`;
    const document:MeetingDocument={session:{id,title:id==="launch"?"Pilot launch check-in":"Support handover",startedAt:started,endedAt:started,state:"noted",attendees:[],speakers:["Sam","Priya"],engine:"Notes",noteSource:"Synthetic sample",duration:0,segmentCount:0},transcript:[],bullets:[],note:source.evidence.map((e,j)=>`## ${["Decision","Details to confirm","Follow-through"][j] || "Source"}\n\n${e.text}`).join("\n\n")};
    return {id,title:document.session.title,started_at:started,updated_at:started,version:1,deleted_at:null,document};
  });
}
export type PreviewState="normal"|"slow"|"empty"|"error"|"reader-error"|"review-readonly"|"review-signed-out";
export function createWorkspacePreview(storage?:Storage,state:PreviewState="normal") {
  const wait=async()=>{if(state==="slow")await new Promise(resolve=>setTimeout(resolve,2500));};
  let accounts:(MailIdentity & {email:string;signature:string})[]=initialAccounts.map(a=>({...a}));
  const identityKey="concourse:mail-identity-fixture:v1";
  let notes=initialNotes(),drafts:Record<string,{message:Compose;revision:number}>={};
  let workspaceDrafts:Record<string,{id:string;connection_id:string;document:Compose;version:number;gmail_state:string;gmail_error:null;updated_at:string}>={};
  try{workspaceDrafts=JSON.parse(storage?.getItem(MAIL_DRAFT_KEY) || "{}");}catch{throw Error("Sample Concourse draft storage could not be read.");}
  let identityError="",storageError="",baseline:string|null=null;
  try {const saved=storage?.getItem(KEY);baseline=saved ?? null;if(saved){const parsed=JSON.parse(saved);if(!Array.isArray(parsed.notes)||!parsed.drafts||typeof parsed.drafts!=="object")throw Error();notes=parsed.notes.map((r:CloudSession)=>({...r,document:documentSchema.parse(r.document)}));drafts=parsed.drafts;}}
  catch {storageError="This sample workspace’s saved data could not be read. Its original data has been preserved.";}
  const write=(nextNotes=notes,nextDrafts=drafts)=>{
    if(storageError)throw Error(storageError);
    if(!storage)throw Error("Browser sample storage is unavailable. Keep your edits open.");
    if(storage.getItem(KEY)!==baseline)throw Error("This sample workspace changed in another tab. Reload before saving; your browser draft is kept.");
    const serialised=JSON.stringify({notes:nextNotes,drafts:nextDrafts});storage.setItem(KEY,serialised);baseline=serialised;notes=nextNotes;drafts=nextDrafts;
  };
  try {const raw=storage?.getItem(identityKey);if(raw){const saved=JSON.parse(raw);accounts=accounts.map(a=>{const p=saved[a.id];if(!p)return a;if((p.identity_colour!=null&&!mailboxColours.includes(p.identity_colour))||(p.identity_icon!=null&&!mailboxIcons.includes(p.identity_icon))||typeof p.signature!=="string")throw Error();return {...a,...p};});}}
  catch {identityError="Saved sample mailbox preferences could not be read. Original storage is preserved.";}
  const threads=[
    {...message("pilot","Pilot launch check-in","Priya <priya@example.com>","Hi Sam,\n\nThanks for the check-in. We agreed to start with a small pilot group. The onboarding checklist still needs an owner, and the final launch date is not confirmed.\n\nCould we review the checklist on Friday at 10? We haven’t agreed a date, time zone or duration. Please suggest a time once the owner is confirmed.\n\nPriya","2026-09-30T09:42:00Z"),account_id:"sample-work",count:2,snippet:"Could we review the checklist on Friday at 10?",unread:true,starred:false},
    {...message("support","Support handover","Priya <priya@example.com>","Hi Sam,\n\nLet’s confirm the handover owner before publishing the support plan. No deadline has been agreed yet.\n\nPriya","2026-09-29T15:20:00Z"),account_id:"sample-work",count:1,snippet:"Confirm the handover owner before publishing.",unread:false,starred:false},
    {...message("walk","Saturday walk","Alex <alex@example.com>","Fancy a walk on Saturday? We can decide on the meeting point later.\n\nAlex","2026-09-28T10:00:00Z"),to:"sam.personal@example.com",account_id:"sample-personal",count:1,snippet:"Fancy a walk on Saturday?",unread:false,starred:false},
  ];
  // Trusted fixture of the server-sanitised contract, never source_html.
  threads.push({...message("rich-update","Product update · formatted sample","Concourse sample <updates@example.invalid>","Synthetic newsletter. Safe formatting and embedded images are retained. Images load when the message opens.","2026-09-30T08:00:00Z"),html:`<table width="600" cellpadding="24" style="border-collapse:collapse;background-color:#ffffff"><tbody><tr><td style="background-color:#eef0fb;color:#343f82;font-family:Arial, sans-serif;font-size:28px;padding:24px"><strong>A little more room for your work.</strong></td></tr><tr><td style="font-family:Arial, sans-serif;font-size:16px;line-height:1.6;padding:24px"><p>This is a synthetic formatted email for Concourse QA. Table layout, colours and spacing stay in the message.</p><img alt="Embedded sample mark" width="32" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==" referrerpolicy="no-referrer"><p>Embedded images belong to this message. Remote images load when you open the message.</p><img alt="Concourse remote sample image" width="480" height="120" data-concourse-image-src="https://placehold.co/480x120/png?text=Concourse+sample" referrerpolicy="no-referrer">${Array.from({length:12},(_,i)=>`<p><strong>Update ${i+1}</strong><br>Keep your mail in context, with a readable layout and a conversation that scrolls all the way to the final actions.</p>`).join("")}<p><strong>End of synthetic message.</strong></p></td></tr></tbody></table>`,account_id:"sample-work",count:1,snippet:"Safe formatting and automatic image loading.",unread:false,starred:false});
  const mail:MailRequest=async(params={},body)=>{
    await wait();
    if(state==="error")throw Error("Simulated mail loading failure. Choose Normal in Preview state to recover.");
    if(body){const b=body as {action:string;account?:string;id?:string;signature?:string;identity_colour?:MailIdentity["identity_colour"];identity_icon?:MailIdentity["identity_icon"];message?:Compose;workspace_id?:string;workspace_version?:number};
      if(b.action==="send"||b.action==="dispatch"||b.action==="retry")throw Error("Sending is unavailable in the synthetic preview.");
      if(b.action==="workspace_draft"&&b.message&&b.workspace_id){
        if(!storage)throw Error("Sample draft storage is unavailable.");
        const current=JSON.parse(storage.getItem(MAIL_DRAFT_KEY) || "{}"),existing=current[b.workspace_id];
        if(existing&&JSON.stringify(existing.document)===JSON.stringify(b.message))return {workspace_id:existing.id,workspace_version:existing.version,id:existing.document.id,revision:existing.document.revision,concourse_saved:true,gmail_saved:true};
        if((existing?.version || 0)!==b.workspace_version)throw Error("This Concourse draft changed in another session. Reopen it before saving; device edits are kept.");
        const id=b.message.id || crypto.randomUUID(),revision=(drafts[id]?.revision || 0)+1;
        const document={...b.message,id,revision:String(revision)},row={id:b.workspace_id,connection_id:document.connection_id,document,version:(existing?.version || 0)+1,gmail_state:"synced",gmail_error:null,updated_at:new Date().toISOString()};
        write(notes,{...drafts,[id]:{message:document,revision}});storage.setItem(MAIL_DRAFT_KEY,JSON.stringify({...current,[row.id]:row}));workspaceDrafts={...current,[row.id]:row};
        return {workspace_id:row.id,workspace_version:row.version,id,revision:String(revision),concourse_saved:true,gmail_saved:true};
      }
      if(b.action==="draft" && b.message){const id=b.message.id || crypto.randomUUID(),existing=drafts[id];if(existing&&b.message.revision!==String(existing.revision))throw Error("This sample draft changed. Reopen it before saving.");const revision=(existing?.revision || 0)+1;write(notes,{...drafts,[id]:{message:b.message,revision}});return {id,revision:String(revision)};}
      if(b.action==="preferences"){
        const index=accounts.findIndex(a=>a.id===b.account);if(index<0)throw Error("Unknown sample mailbox.");
        if(identityError)throw Error(identityError);if(!storage)throw Error("Browser sample storage is unavailable. Your edits remain open.");
        const next={...accounts[index],signature:b.signature ?? accounts[index].signature,identity_colour:b.identity_colour === undefined?accounts[index].identity_colour:b.identity_colour,identity_icon:b.identity_icon === undefined?accounts[index].identity_icon:b.identity_icon};
        const raw=storage.getItem(identityKey),saved=raw?JSON.parse(raw):{};
        storage.setItem(identityKey,JSON.stringify({...saved,[next.id]:{signature:next.signature,identity_colour:next.identity_colour ?? null,identity_icon:next.identity_icon ?? null}}));accounts[index]=next;return {saved:true};
      }
      const thread=threads.find(t=>t.id===b.id&&t.account_id===b.account);if(!thread)throw Error("Sample conversation not found.");
      if(b.action==="read")thread.unread=false;
      else if(b.action==="unread")thread.unread=true;
      else if(b.action==="star"||b.action==="unstar")thread.starred=b.action==="star";
      else if(b.action==="archive")thread.labels=thread.labels.filter(l=>l!=="INBOX");
      else if(b.action==="trash")thread.labels=["TRASH"];
      else if(b.action==="restore")thread.labels=["INBOX"];
      else throw Error("This action is unavailable in the synthetic preview.");
      return {ok:true};
    }
    if(params.workspace_drafts)return {drafts:Object.values(JSON.parse(storage?.getItem(MAIL_DRAFT_KEY) || "{}"))};
    if(params.workspace_draft)return {draft:workspaceDrafts[params.workspace_draft] || null};
    if(!params.account)return {accounts,outbox:[]};
    if(!accounts.some(a=>a.id===params.account))throw Error("Unknown sample mailbox.");
    if(params.labels)return {labels:[]};
    if(params.forward)return {attachments:[]};
    if(params.draft){const d=drafts[params.draft];if(!d||d.message.connection_id!==params.account)throw Error("Sample draft not found.");return {revision:String(d.revision),attachments:d.message.attachments,message:{...message(params.draft,d.message.subject,accounts.find(a=>a.id===params.account)!.email,d.message.text,"2026-09-30T10:00:00Z"),to:d.message.to.join(", "),cc:d.message.cc.join(", "),bcc:d.message.bcc.join(", ")}};}
    if(params.drafts)return {drafts:Object.entries(drafts).filter(([,d])=>d.message.connection_id===params.account).map(([id,d])=>({id,message:{subject:d.message.subject,to:d.message.to.join(", ")}})),next_page:null};
    const own=threads.filter(t=>t.account_id===params.account);
    if(params.thread){if(state==="reader-error")throw Error("Simulated conversation loading failure. Choose Normal in Preview state to recover.");const t=own.find(t=>t.id===params.thread);if(!t)throw Error("Sample conversation not found.");return {messages:t.id==="pilot"?[{...message("pilot-earlier","Pilot launch check-in","Sam <sam@example.com>","Hi Priya, can we agree the checklist owner before setting a launch date?","2026-09-30T08:30:00Z"),thread_id:t.id,to:"priya@example.com",labels:["SENT"]},t]:[t]};}
    const q=params.q || "in:inbox";
    let visible=q.includes("-in:inbox")?own.filter(t=>!t.labels.includes("INBOX")&&!t.labels.includes("TRASH")):q.includes("in:trash")?own.filter(t=>t.labels.includes("TRASH")):q.includes("is:starred")?own.filter(t=>t.starred):q.includes("in:sent")||q.includes("in:spam")?[]:own.filter(t=>t.labels.includes("INBOX"));
    const search=q.split(/\s+/).filter(term=>!/^[-]?(in:|is:)/.test(term)).join(" ").toLowerCase();
    if(search)visible=visible.filter(t=>`${t.subject} ${t.from} ${t.text}`.toLowerCase().includes(search));
    return {threads:state==="empty"?[]:visible,next_page:null};
  };
  const notesRequest:typeof fetch=async(input,init)=>{
    await wait();
    const url=new URL(String(input),"http://synthetic.local"),reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"Content-Type":"application/json"}});
    if(url.pathname!=="/api/sessions"&&!url.pathname.startsWith("/api/sessions/"))return reply({error:"This request is unavailable in the synthetic preview."},400);
    if(state==="error")return reply({error:"Simulated notes loading failure. Choose Normal in Preview state to recover."},503);
    if(storageError)return reply({error:storageError},409);
    const followUpID=url.pathname.match(/^\/api\/sessions\/([^/]+)\/follow-up$/)?.[1];
    const currentNotes=()=>{const raw=storage?.getItem(KEY);return raw?JSON.parse(raw).notes.map((r:CloudSession)=>({...r,document:documentSchema.parse(r.document)})):notes;};
    if(followUpID) {
      if(state==="review-readonly")return reply({error:"This synthetic connection has read-only access. Sign in to Concourse to edit follow-ups."},403);
      if(state==="review-signed-out")return reply({error:"Synthetic sign-in expired. Your local edits remain; sign in again to save."},401);
      try {
        if(!storage)throw Error("Synthetic server storage is unavailable.");
        const source=currentNotes().find((r:CloudSession)=>r.id===decodeURIComponent(followUpID)&&!r.deleted_at);
        if(!source)return reply({error:"This note is not in the sample library."},404);
        const raw=storage.getItem(FOLLOW_UP_KEY),saved:Record<string,SavedFollowUp>=raw?JSON.parse(raw):{};
        const existing=saved[source.id] || null;
        if(init?.method==="PUT") {
          const parsed=followUpWrite.safeParse(JSON.parse(String(init.body)));if(!parsed.success)return reply({error:"Check the draft fields and missing details."},400);
          const {document,expectedVersion}=parsed.data;
          if(document.sourceVersion!==source.version)return reply({error:"The source note changed. Your edits are retained."},409);
          for(const item of document.evidence) {
            const text=item.kind==="note"&&item.id==="note"?source.document.note:item.kind==="transcript"?source.document.transcript.find((line:MeetingDocument["transcript"][number])=>line.id===item.id)?.text:item.kind==="bullet"?source.document.bullets.find((line:MeetingDocument["bullets"][number])=>line.id===item.id)?.text:null;
            if(!text?.includes(item.text))return reply({error:"Evidence does not match the current note."},400);
          }
          if(existing&&JSON.stringify(existing.document)===JSON.stringify(document))return reply({draft:existing});
          if(expectedVersion!==(existing?.version || 0))return reply({error:"This follow-up changed in another session. Compare both versions."},409);
          const draft={session_id:source.id,document,version:(existing?.version || 0)+1,updated_at:new Date().toISOString()};
          storage.setItem(FOLLOW_UP_KEY,JSON.stringify({...saved,[source.id]:draft}));return reply({draft});
        }
        if(init?.method && init.method!=="GET")return reply({error:"No send or other mutation exists in this fixture."},405);
        return reply(effectiveFollowUp(existing,source.version));
      } catch(e){return reply({error:e instanceof Error?e.message:"Synthetic server copy could not be read."},409);}
    }
    if(init?.method==="POST"){
      try {const b=JSON.parse(String(init.body)),document=documentSchema.parse(b.document),existing=notes.find(r=>r.id===document.session.id);if(b.expectedVersion!==(existing?.version || 0))return reply({error:"This sample note changed. Reload before saving."},409);
        const row:CloudSession={id:document.session.id,title:document.session.title,document,started_at:document.session.startedAt,updated_at:new Date().toISOString(),version:(existing?.version || 0)+1,deleted_at:b.deleted?new Date().toISOString():null};write([...notes.filter(r=>r.id!==row.id),row]);return reply(row);
      } catch(e){return reply({error:e instanceof Error?e.message:"Sample storage is unavailable."},400);}
    }
    if(url.pathname.startsWith("/api/sessions/")){const row=currentNotes().find((r:CloudSession)=>r.id===url.pathname.split("/").pop());return row?reply(row):reply({error:"Sample note not found."},404);}
    return reply({sessions:state==="empty"?[]:notes,nextOffset:null});
  };
  return {mail,notes:notesRequest};
}
