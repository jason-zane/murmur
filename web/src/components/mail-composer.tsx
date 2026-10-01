"use client";
import {useState,useRef,useEffect,useCallback,useImperativeHandle,type Ref} from "react";
import {Send,X} from "lucide-react";
import type {Compose} from "@/lib/mail/model";
import {addresses,emailAddress} from "@/lib/mail/recipients";
import {DraftEdits} from "@/lib/mail/draft-edits";
import {Dialog} from "./dialog";
import {MailboxBadge,type MailAccountPreference} from "./mail-preferences";
import type {MailRequest} from "./mail-workspace";
export type LocalDraft=Compose&{local_key?:string;scheduled?:string;scheduled_at?:string;workspace_id?:string;workspace_version?:number};
export type MailComposerHandle={saveAndClose:()=>Promise<boolean>};
const localTime=(iso?:string)=>{if(!iso)return "";const d=new Date(iso),pad=(n:number)=>String(n).padStart(2,"0");return Number.isNaN(d.getTime())?"":`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;};
type Binding={id?:string;revision?:string;workspace_id:string;workspace_version:number;thread_id?:string};
export function MailComposer({initial,accounts,userID,onClose,onSent,request,previewMode=false,inline=false,mode="New message",ref}:{initial:LocalDraft;accounts:MailAccountPreference[];userID:string;onClose:()=>void;onSent:()=>void;request:MailRequest;previewMode?:boolean;inline?:boolean;mode?:string;ref?:Ref<MailComposerHandle>}) {
 const [value,setValue]=useState(initial),[to,setTo]=useState(initial.to.join(", ")),[cc,setCc]=useState(initial.cc.join(", ")),[bcc,setBcc]=useState(initial.bcc.join(", ")),[error,setError]=useState(""),[status,setStatus]=useState(""),[busy,setBusy]=useState(false),[attaching,setAttaching]=useState(false),[scheduled,setScheduled]=useState(initial.scheduled || localTime(initial.scheduled_at));
 const edits=useRef(new DraftEdits(Boolean(initial.local_key))),saving=useRef(Promise.resolve()),savedOK=useRef(true),recoveredOK=useRef(true),lock=useRef(false),operationID=useRef(crypto.randomUUID()),bodyRef=useRef<HTMLTextAreaElement>(null);
 const bindings=useRef(new Map<string,Binding>([[initial.connection_id,{id:initial.id,revision:initial.revision,workspace_id:initial.workspace_id || crypto.randomUUID(),workspace_version:initial.workspace_version || 0,thread_id:initial.thread_id}]]));
 const binding=bindings.current.get(value.connection_id)!;
 const storageKey=(b:Binding,account:string)=>`voice-notes:draft:${userID}:${account}:${b.workspace_id}`;
 const edit=()=>edits.current.edit();
 const message=()=>({...value,scheduled_at:scheduled&&!Number.isNaN(new Date(scheduled).getTime())?new Date(scheduled).toISOString():undefined,id:binding.id,revision:binding.revision,thread_id:binding.thread_id,to:addresses(to).map(emailAddress),cc:addresses(cc).map(emailAddress),bcc:addresses(bcc).map(emailAddress)});
 const snapshot=message();
 const latest=useRef(snapshot);latest.current=snapshot;
 const persistDevice=useCallback((v:Compose,b:Binding)=>{
  try{localStorage.setItem(storageKey(b,v.connection_id),JSON.stringify({...v,workspace_id:b.workspace_id,workspace_version:b.workspace_version,scheduled}));recoveredOK.current=true;}catch{recoveredOK.current=false;}
 },[userID,scheduled]);
 // Capture immediately, before a route change or tab interruption can beat the debounce.
 useEffect(()=>{if(edits.current.dirty)persistDevice(snapshot,binding);},[value,to,cc,bcc,scheduled,persistDevice]);
 useEffect(()=>{
  const handler=(event:BeforeUnloadEvent)=>{if(edits.current.dirty){persistDevice(latest.current,bindings.current.get(latest.current.connection_id)!);if(!recoveredOK.current){event.preventDefault();}}};
  window.addEventListener("beforeunload",handler);return()=>window.removeEventListener("beforeunload",handler);
 },[persistDevice]);
 useEffect(()=>{if(inline){bodyRef.current?.focus({preventScroll:true});requestAnimationFrame(()=>bodyRef.current?.closest(".mail-inline-composer")?.scrollIntoView({block:"end"}));}},[inline]);
 const save=useCallback(async()=>{
  if(!edits.current.dirty){await saving.current;return;}
  const v=latest.current,b=bindings.current.get(v.connection_id)!,run=edits.current.capture();persistDevice(v,b);
  saving.current=saving.current.catch(()=>{}).then(async()=>{
   try{
    setStatus(previewMode?"Saving sample draft…":"Saving in Concourse and Gmail…");
    const result=await request({}, {action:"workspace_draft",workspace_id:b.workspace_id,workspace_version:b.workspace_version,message:{...v,id:b.id,revision:b.revision}});
    b.workspace_version=result.workspace_version;b.id=result.id;b.revision=result.revision;
    savedOK.current=Boolean(result.gmail_saved);recoveredOK.current=Boolean(result.concourse_saved)||recoveredOK.current;
    if(edits.current.acknowledge(run)){
     setStatus(previewMode?"Sample saved in this browser · no Gmail connection":result.gmail_saved?"Saved in Concourse and Gmail":"Saved in Concourse · Gmail sync incomplete");
     setError(result.gmail_error || "");
     if(result.concourse_saved){try{localStorage.removeItem(storageKey(b,v.connection_id));if(initial.local_key)localStorage.removeItem(initial.local_key);}catch{}}
    }else persistDevice(latest.current,bindings.current.get(latest.current.connection_id)!);
   }catch(e){savedOK.current=false;setStatus(recoveredOK.current?"Saved on this device · cloud save incomplete":"Draft could not save · keep it open");setError((e as Error).message);}
  });await saving.current;
 },[request,previewMode,persistDevice,userID,initial.local_key]);
 useEffect(()=>{const timer=setTimeout(()=>void save(),1200);return()=>clearTimeout(timer);},[save,value,to,cc,bcc,scheduled]);
 async function close(){if(lock.current||attaching)return false;lock.current=true;setBusy(true);try{await save();if(recoveredOK.current){onClose();return true;}return false;}finally{lock.current=false;setBusy(false);}}
 useImperativeHandle(ref,()=>({saveAndClose:close}));
 async function switchSender(account:string){
  if(lock.current||account===value.connection_id||attaching)return;lock.current=true;setBusy(true);
  try{
   await save();if(!recoveredOK.current){setError("Keep this draft open until it can be saved before changing sender.");return;}
   if(!bindings.current.has(account))bindings.current.set(account,{workspace_id:crypto.randomUUID(),workspace_version:0});
   // Provider IDs and thread IDs belong to their mailbox. Body and recipients stay intact.
   edit();setValue(old=>({...old,connection_id:account,id:undefined,revision:undefined,thread_id:undefined}));operationID.current=crypto.randomUUID();setError("");setStatus("Sender changed · your wording and recipients are kept");
  }finally{lock.current=false;setBusy(false);}
 }
 async function send(){
  if(previewMode||lock.current||attaching)return;lock.current=true;setBusy(true);setError("");
  try{await save();if(!savedOK.current)throw Error("Resolve Gmail sync before sending. Your draft remains in Concourse.");await request({}, {action:"send",operation_id:operationID.current,workspace_id:binding.workspace_id,message:{...latest.current,id:binding.id,revision:binding.revision},...(scheduled?{due_at:new Date(scheduled).toISOString()}:{})});try{localStorage.removeItem(storageKey(binding,value.connection_id));}catch{}onSent();}catch(e){setError((e as Error).message);}finally{lock.current=false;setBusy(false);}
 }
 async function attach(files:FileList|null){
  const chosen=Array.from(files || []);if(value.attachments.length+chosen.length>20){setError("Use at most 20 attachments.");return;}setAttaching(true);
  try{let total=value.attachments.reduce((n,a)=>n+a.data.length*.75,0);for(const file of chosen){if(total+file.size>18000000)throw Error("Attachments must total less than 18 MB.");total+=file.size;const data=await new Promise<string>((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(String(reader.result).split(",")[1]);reader.onerror=reject;reader.readAsDataURL(file);});edit();setValue(v=>({...v,attachments:[...v.attachments,{name:file.name,type:file.type || "application/octet-stream",data}]}));}}catch(e){setError(e instanceof Error?e.message:"This attachment could not be read.");}finally{setAttaching(false);}
 }
 const attachmentFields=<><div className="mail-attachments">{value.attachments.map((a,i)=><button key={`${a.name}-${i}`} className="button small" disabled={busy||attaching} onClick={()=>{edit();setValue(v=>({...v,attachments:v.attachments.filter((_,n)=>n!==i)}));}}>{a.name}<X size={14}/></button>)}</div><label className="field"><span>Attachments</span><input type="file" disabled={busy||attaching} multiple onChange={e=>void attach(e.target.files)}/></label><label className="field"><span>Send later (optional)</span><input type="datetime-local" disabled={busy} value={scheduled} onChange={e=>setScheduled(e.target.value)}/></label></>;
 const content=<section className={"mail-composer"+(inline?" mail-inline-composer":"")} aria-label={mode+" draft"} onChangeCapture={event=>{if(event.target!==event.currentTarget.querySelector('[aria-label="From address"]'))edit();}}>
  <header><h2>{mode}</h2><button className="icon-button" aria-label="Save draft and close" disabled={busy||attaching} onClick={()=>void close()}><X size={18}/></button></header>
  {!inline&&<p className="fine-print">{previewMode?"Synthetic draft · saved in this browser only":"Email draft · autosaves in Concourse and Gmail. Notes save in Concourse."}</p>}
  {error&&<p className="notice" role="alert">{error}<button className="text-link" disabled={busy||attaching} onClick={()=>{edit();void save();}}>Retry save</button></p>}
  {!inline&&<MailboxBadge account={accounts.find(a=>a.id===value.connection_id) || {id:value.connection_id}}/>}
  <div className={inline?"form-grid mail-inline-addresses":""}><label className="field"><span>From</span><select aria-label="From address" disabled={busy||attaching} value={value.connection_id} onChange={e=>void switchSender(e.target.value)}>{accounts.map(a=><option key={a.id} value={a.id}>{a.email}</option>)}</select></label>
  <label className="field"><span>To</span><input autoFocus={!inline} disabled={busy} value={to} onChange={e=>setTo(e.target.value)}/></label></div>
  {inline?<details className="mail-compose-options"><summary>Cc, Bcc, subject and attachments</summary><div className="form-grid"><label className="field"><span>Cc</span><input disabled={busy} value={cc} onChange={e=>setCc(e.target.value)}/></label><label className="field"><span>Bcc</span><input disabled={busy} value={bcc} onChange={e=>setBcc(e.target.value)}/></label></div>
  <label className="field"><span>Subject</span><input disabled={busy} value={value.subject} onChange={e=>setValue(v=>({...v,subject:e.target.value}))}/></label>{attachmentFields}</details>:<><div className="form-grid"><label className="field"><span>Cc</span><input disabled={busy} value={cc} onChange={e=>setCc(e.target.value)}/></label><label className="field"><span>Bcc</span><input disabled={busy} value={bcc} onChange={e=>setBcc(e.target.value)}/></label></div>
  <label className="field"><span>Subject</span><input disabled={busy} value={value.subject} onChange={e=>setValue(v=>({...v,subject:e.target.value}))}/></label></>}
  <label className="field"><span>Message</span><textarea ref={bodyRef} rows={inline?4:12} disabled={busy||Boolean(value.html)} value={value.text || (value.html?"Formatted draft preserved. Switch to plain text to edit its body.":"")} onChange={e=>setValue(v=>({...v,text:e.target.value}))}/></label>
  {value.html&&<p className="notice">Original formatting is preserved. <button className="text-link" disabled={busy||attaching} onClick={()=>{if(confirm("Convert this formatted draft to plain text? Its layout and inline images will be removed.")){edit();setValue(v=>({...v,html:undefined}));}}}>Switch to plain text…</button></p>}
  {(error.includes("changed")||error.includes("unconfirmed"))&&<button className="button" disabled={busy||attaching} onClick={()=>{bindings.current.set(value.connection_id,{workspace_id:crypto.randomUUID(),workspace_version:0,thread_id:binding.thread_id});operationID.current=crypto.randomUUID();edit();setValue(v=>({...v,id:undefined,revision:undefined}));setError("");}}>Keep my edits as a new draft</button>}
  {!inline&&  <details className="mail-compose-options"><summary>Attachments and send later{value.attachments.length?` · ${value.attachments.length} attached`:""}</summary><div className="mail-attachments">{value.attachments.map((a,i)=><button key={`${a.name}-${i}`} className="button small" disabled={busy||attaching} onClick={()=>{edit();setValue(v=>({...v,attachments:v.attachments.filter((_,n)=>n!==i)}));}}>{a.name}<X size={14}/></button>)}</div><label className="field"><span>Attachments</span><input type="file" disabled={busy||attaching} multiple onChange={e=>void attach(e.target.files)}/></label><label className="field"><span>Send later (optional)</span><input type="datetime-local" disabled={busy} value={scheduled} onChange={e=>setScheduled(e.target.value)}/></label></details>}

  <footer><span role="status">{status || (previewMode?"Synthetic draft · browser only":"Autosaves in Concourse and Gmail")}</span><div className="mail-compose-buttons"><button className="button" disabled={busy||attaching} onClick={()=>void close()}>Save and close</button><button className="button primary" disabled={previewMode||busy||attaching} onClick={()=>void send()}><Send size={16}/>{previewMode?"Sending unavailable":busy?"Saving…":scheduled?"Schedule send":"Send"}</button></div></footer>
 </section>;
 return inline?content:<Dialog label={mode} onClose={()=>void close()}>{content}</Dialog>;
}
