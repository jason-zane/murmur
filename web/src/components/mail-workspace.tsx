"use client";
import { useState,useEffect,useRef,useCallback } from "react";
import { Mail,Inbox,Send,FileText,Archive,Star,Trash2,RefreshCw,Search,Plus,ArrowLeft,Paperclip,X } from "lucide-react";
import { DraftEdits } from "@/lib/mail/draft-edits";
import { Dialog } from "./dialog";
import { Shell } from "./shell";
import type { Compose,MailMessage } from "@/lib/mail/model";
type LocalDraft=Compose & {local_key?:string;scheduled?:string};
type Account={id:string;email:string;error?:string;signature?:string};
type Thread=MailMessage & {account_id:string;count:number;snippet:string;unread:boolean;starred:boolean};
type Outbox={id:string;connection_id:string;subject:string;status:string;due_at:string;error?:string};
const folders=[{id:"in:inbox",label:"Inbox",icon:Inbox},{id:"is:starred",label:"Starred",icon:Star},{id:"in:sent",label:"Sent",icon:Send},{id:"drafts",label:"Drafts",icon:FileText},{id:"in:all -in:inbox -in:spam -in:trash",label:"Archive",icon:Archive},{id:"in:spam",label:"Spam",icon:Mail},{id:"in:trash",label:"Bin",icon:Trash2}];
async function api(params:Record<string,string>={},body?:unknown) {
 const r=await fetch(`/api/mail?${new URLSearchParams(params)}`,body?{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)}:{});
 const b=await r.json();if(!r.ok) throw new Error(b.error || "Mail could not complete this request.");return b;
}
const addresses=(value:string)=>{
 const result:string[]=[];let buffer="",quoted=false,escaped=false,depth=0;
 for(const character of value){
  if(escaped){buffer+=character;escaped=false;continue;}
  if(character==="\\"&&quoted){buffer+=character;escaped=true;continue;}
  if(character==='"')quoted=!quoted;
  if(!quoted){if(character==="<")depth++;if(character===">")depth=Math.max(0,depth-1);}
  if(!quoted&&depth===0&&(character===","||character===";")){if(buffer.trim())result.push(buffer.trim());buffer="";}else buffer+=character;
 }
 if(buffer.trim())result.push(buffer.trim());return result;
};
const emailAddress=(value:string)=>value.match(/<([^>]+)>/)?.[1] || value.trim();
export function MailWorkspace({email,userID,googleReady}:{email:string;userID:string;googleReady:boolean}) {
 const [accounts,setAccounts]=useState<Account[]>([]),[account,setAccount]=useState(""),[folder,setFolder]=useState("in:inbox"),[query,setQuery]=useState(""),[search,setSearch]=useState(""),[threads,setThreads]=useState<Thread[]>([]),[pages,setPages]=useState<Record<string,string|null>>({}),[selected,setSelected]=useState<Thread|null>(null),[messages,setMessages]=useState<MailMessage[]>([]),[outbox,setOutbox]=useState<Outbox[]>([]),[labels,setLabels]=useState<{id:string;name:string}[]>([]),[drafts,setDrafts]=useState<{id:string;message:MailMessage;account_id:string}[]>([]),[busy,setBusy]=useState(false),[error,setError]=useState(""),[notice,setNotice]=useState(""),[composer,setComposer]=useState<LocalDraft|null>(null),[localDrafts,setLocalDrafts]=useState<LocalDraft[]>([]),[checks,setChecks]=useState<Set<string>>(new Set());
 const [preferencesOpen,setPreferencesOpen]=useState(false);
 const version=useRef(0),readerVersion=useRef(0),composerOpen=useRef(false);
 composerOpen.current=Boolean(composer);
 const loadAccounts=useCallback(async()=>{const b=await api();try {const prefix=`voice-notes:draft:${userID}:`;const cached=Object.keys(localStorage).filter(k=>k.startsWith(prefix)).map(k=>({...JSON.parse(localStorage.getItem(k)!),local_key:k}));setLocalDrafts(cached);}catch{}setAccounts(b.accounts);setOutbox(b.outbox);return b.accounts as Account[];},[userID]);
 async function load(more=false) {
  const run=++version.current;setBusy(true);setError("");
  try {
   const all=await loadAccounts();if(folder==="outbox") return;const chosen=all.filter(a=>!account || a.id===account),next:Record<string,string|null>={},items:Thread[]=[],draftItems:typeof drafts=[];
   const results=await Promise.allSettled(chosen.filter(a=>!more || pages[a.id]).map(async a=>{
    if(folder==="drafts") {const b=await api({account:a.id,drafts:"1",...(more&&pages[a.id]?{page:pages[a.id]!}:{})});next[a.id]=b.next_page;draftItems.push(...(b.drafts || []).map((d:{id:string;message:MailMessage})=>({...d,account_id:a.id})));return;}
    const b=await api({account:a.id,q:search?`${folder} ${search}`:folder,...(more&&pages[a.id]?{page:pages[a.id]!}:{})});
    items.push(...b.threads.map((t:Thread)=>({...t,account_id:a.id})));next[a.id]=b.next_page;
   }));
   if(run!==version.current) return;
   const failures=results.filter((r):r is PromiseRejectedResult=>r.status==="rejected");
   if(failures.length) setError(failures.map(r=>r.reason instanceof Error?r.reason.message:"An inbox could not update.").join(" · "));
   if(failures.length===results.length && results.length) return;
   setDrafts(old=>more?[...old,...draftItems]:draftItems);setPages(more?{...pages,...next}:next);
   setThreads(old=>{const map=new Map((more?old:[]).concat(items).map(t=>[`${t.account_id}|${t.id}`,t]));return [...map.values()].sort((a,b)=>Date.parse(b.date)-Date.parse(a.date));});
  } catch(e) {if(run===version.current) setError(e instanceof Error?e.message:"Mail could not update.");} finally {if(run===version.current) setBusy(false);}
 }
 useEffect(()=>{void load();const timer=setInterval(()=>{if(document.visibilityState==="visible" && !composerOpen.current) void load();},30000);return()=>{clearInterval(timer);version.current++;};},[account,folder,search]);
 useEffect(()=>{if(!account){setLabels([]);return;}let active=true;api({account,labels:"1"}).then(b=>{if(active) setLabels(b.labels.filter((l:{type:string})=>l.type==="user"));}).catch(e=>setError(e.message));return()=>{active=false;};},[account]);
 useEffect(()=>{const timer=setInterval(()=>{void api({}, {action:"dispatch"}).then(loadAccounts).catch(()=>{});},15000);return()=>clearInterval(timer);},[loadAccounts]);
 useEffect(()=>{const handle=(e:KeyboardEvent)=>{if(e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement || e.target instanceof HTMLSelectElement || composer) return;if(e.key==="c"){e.preventDefault();compose();}if(e.key==="Escape"){setSelected(null);setChecks(new Set());}if(e.key==="e" && selected){e.preventDefault();void act("archive",selected);}if(e.key==="j" || e.key==="k"){e.preventDefault();const i=selected?threads.findIndex(t=>t.id===selected.id&&t.account_id===selected.account_id):-1;const next=threads[Math.max(0,Math.min(threads.length-1,i+(e.key==="j"?1:-1)))];if(next) void open(next);}};window.addEventListener("keydown",handle);return()=>window.removeEventListener("keydown",handle);},[threads,selected,composer,accounts,account]);
 async function compose(message?:MailMessage,replyAll=false,forward=false) {
  const sender=message?selected?.account_id:account || accounts[0]?.id;if(!sender){setNotice("Connect a Gmail inbox to compose a message.");return;}
  let attachments:Compose["attachments"]=[];
  if(forward&&message) {try {const b=await api({account:sender,forward:message.id});attachments=b.attachments.map((a:{name:string;type:string;data:string;cid?:string})=>({name:a.name,type:a.type,data:a.data,cid:a.cid}));}catch(e){setError((e as Error).message);return;}}
  const senderAccount=accounts.find(a=>a.id===sender),own=senderAccount?.email || "",signature=senderAccount?.signature?`\n\n${senderAccount.signature}`:"";
  const recipients=message&&!forward?[emailAddress(message.reply_to || message.from),...(replyAll?addresses(message.to).map(emailAddress):[])].filter(v=>v.toLowerCase()!==own.toLowerCase()):[];
  setComposer({connection_id:sender,to:[...new Set(recipients)],cc:replyAll&&message?addresses(message.cc).map(emailAddress).filter(v=>v.toLowerCase()!==own.toLowerCase()):[],bcc:[],subject:message?`${forward?"Fwd: ":/^re:/i.test(message.subject)?"":"Re: "}${message.subject}`:"",text:forward&&message?`${signature}\n\n---------- Forwarded message ----------\nFrom: ${message.from}\nDate: ${message.date}\nSubject: ${message.subject}\n\n${message.text}`:signature,thread_id:message&&!forward?message.thread_id:undefined,in_reply_to:message&&!forward?message.message_id:undefined,references:message&&!forward?`${message.references} ${message.message_id}`.trim():undefined,html:forward&&message?.source_html?`<p>${signature.replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll("\n","<br>")}</p><p>Forwarded message</p><blockquote>${message.source_html}</blockquote>`:undefined,attachments});
 }
 async function open(t:Thread) {
  setSelected(t);setMessages([]);const run=++readerVersion.current;
  try {const b=await api({account:t.account_id,thread:t.id});if(run!==readerVersion.current) return;setMessages(b.messages);if(t.unread) {await api({}, {action:"read",account:t.account_id,id:t.id});setThreads(old=>old.map(v=>v.id===t.id&&v.account_id===t.account_id?{...v,unread:false}:v));}}
  catch(e) {setError(e instanceof Error?e.message:"Could not open this message.");}
 }
 async function act(action:string,t?:Thread,label?:string) {
  const targets=t?[t]:threads.filter(v=>checks.has(`${v.account_id}|${v.id}`));setError("");
  const results=await Promise.allSettled(targets.map(v=>api({}, {action,account:v.account_id,id:v.id,label})));
  const failed=results.filter(r=>r.status==="rejected");if(failed.length) setError(`${failed.length} message actions could not complete. Try again.`);
  setChecks(new Set());if(t && ["archive","trash","spam"].includes(action)) setSelected(null);await load();
 }
 async function openDraft(d:typeof drafts[number]) {try {const b=await api({account:d.account_id,draft:d.id}),m=b.message;setComposer({connection_id:d.account_id,id:d.id,thread_id:m.thread_id,to:addresses(m.to).map(emailAddress),cc:addresses(m.cc).map(emailAddress),bcc:addresses(m.bcc).map(emailAddress),revision:b.revision,subject:m.subject==="(No subject)"?"":m.subject,text:m.text,html:m.source_html || undefined,attachments:b.attachments.map((a:{name:string;type:string;data:string;cid?:string})=>({name:a.name,type:a.type,data:a.data,cid:a.cid})),in_reply_to:m.in_reply_to || undefined,references:m.references || undefined});}catch(e){setError((e as Error).message);}}
 function navigate(nextAccount:string,nextFolder:string) {
  if(nextAccount===account && nextFolder===folder && !search) {readerVersion.current++;setSelected(null);setMessages([]);setChecks(new Set());return;}
  version.current++;readerVersion.current++;setAccount(nextAccount);setFolder(nextFolder);setSelected(null);setMessages([]);setChecks(new Set());setThreads([]);setDrafts([]);setPages({});setSearch("");setQuery("");
 }
 const folderName=folders.find(f=>f.id===folder)?.label || (folder==="outbox"?"Outbox":"Label");
 return <Shell email={email} layout="mail"><header className="page-header"><div className="heading-row"><div><h1>Mail</h1></div><button className="button primary" onClick={()=>compose()} disabled={!accounts.length}><Plus size={17}/>New message</button></div></header>
  {notice && <p className="notice" role="status">{notice}<button className="text-link" onClick={()=>setNotice("")}>Dismiss</button></p>}
  {error && <p className="notice" role="alert">{error}<button className="text-link" onClick={()=>load()}>Try again</button></p>}
  {!accounts.length && !busy?<section className="empty"><Mail size={32}/><h2>Bring your Gmail inbox here</h2><p>Connect work and personal accounts. Read, reply and organise your mail with the correct sender.</p>{googleReady?<a className="button primary" href="/api/google/connect?inbox=1&add=1">Connect Gmail</a>:<p>Google connection setup is required in this installation.</p>}<p className="fine-print">Mail asks for permission to read and manage your inbox. Existing calendar connections stay separate.</p></section>:<div className={"mail-workspace"+(selected?" has-reader":"")}>
   <aside className="mail-folders"><nav aria-label="Mail accounts">
    <button className={"mail-folder"+(!account?" selected":"")} aria-pressed={!account} onClick={()=>navigate("","in:inbox")}><Inbox size={17}/><span>All inboxes</span></button>
    <div className="mail-account-group"><span className="mail-nav-heading">Gmail accounts</span>{accounts.map(a=><div key={a.id}><button title={a.email} aria-label={a.email} aria-pressed={account===a.id} className={"mail-folder mail-account"+(account===a.id?" selected":"")} onClick={()=>navigate(a.id,"in:inbox")}><span className="mail-account-avatar" aria-hidden="true">{a.email[0].toUpperCase()}</span><span className="mail-account-name"><span>{a.email.split("@")[0]}</span><small>{a.email.split("@")[1]}</small></span></button></div>)}</div>
   </nav><nav aria-label={account?"Account folders":"All accounts folders"}><span className="mail-nav-heading">{account?"Folders":"Across all accounts"}</span>{folders.map(f=><button key={f.id} aria-pressed={folder===f.id} className={folder===f.id?"mail-folder selected":"mail-folder"} onClick={()=>navigate(account,f.id)}><f.icon size={17}/>{f.label}</button>)}<button className={folder==="outbox"?"mail-folder selected":"mail-folder"} onClick={()=>navigate(account,"outbox")}><Send size={17}/>Outbox</button>{labels.map(l=><button className="mail-folder" key={l.id} onClick={()=>navigate(account,`label:"${l.name.replaceAll('"','')}"`)}>{l.name}</button>)}</nav><div className="mail-nav-settings"><a className="text-link" href="/api/google/connect?inbox=1&add=1">Add Gmail account</a><button className="text-link" onClick={()=>setPreferencesOpen(true)}>Email signatures</button></div></aside>
   <section className={"mail-list"+(selected?" reader-open":"")} aria-label="Messages"><div className="mail-list-heading"><strong>{folderName}</strong><span title={accounts.find(a=>a.id===account)?.email}>{account?accounts.find(a=>a.id===account)?.email:"All accounts"}</span></div><form className="mail-search" onSubmit={e=>{e.preventDefault();setSearch(query);}}><Search size={17}/><input aria-label="Search mail" placeholder="Search mail · from:, has:attachment…" value={query} onChange={e=>setQuery(e.target.value)}/><button className="icon-button" type="button" aria-label="Refresh mail" onClick={()=>load()}><RefreshCw size={17} className={busy?"spin":""}/></button></form>
    {checks.size>0 && <div className="mail-actions"><span>{checks.size} selected</span><button onClick={()=>act("archive")}>Archive</button><button onClick={()=>act("read")}>Mark read</button><button onClick={()=>act("trash")}>Move to Bin</button></div>}
    <div className="mail-thread-scroll" key={`${account}|${folder}|${search}`}>
    {folder==="drafts" && localDrafts.filter(d=>!account || d.connection_id===account).map(d=><button className="mail-thread" key={d.local_key} onClick={()=>setComposer(d)}><strong>{d.subject || "Untitled draft"}</strong><span>Saved on this device · Continue your unsynchronised edits</span></button>)}
    {folder==="outbox"?outbox.filter(o=>!account || o.connection_id===account).map(o=><div className="mail-outbox-row" key={o.id}><strong>{o.subject || "(No subject)"}</strong><span>{o.status} · {new Date(o.due_at).toLocaleString("en-AU")}</span>{o.error && <p className="notice">{o.error}</p>}{o.status==="failed" && <button className="text-link" onClick={()=>api({}, {action:"retry",id:o.id}).then(loadAccounts).catch(e=>setError(e.message))}>Try sending again</button>}{o.status==="uncertain" && <button className="text-link" onClick={()=>{setAccount(o.connection_id);setFolder("in:sent");setSearch(`rfc822msgid:${o.id}@voice-notes.local`);setQuery(`rfc822msgid:${o.id}@voice-notes.local`);}}>Check Sent mail</button>}{o.status==="queued" && <button className="text-link" onClick={()=>api({}, {action:"cancel",id:o.id}).then(()=>{setNotice("Send cancelled. Your draft remains in Gmail.");return loadAccounts();}).catch(e=>setError(e.message))}>Undo send</button>}</div>):folder==="drafts"?drafts.map(d=><button className="mail-thread" key={`${d.account_id}|${d.id}`} onClick={()=>openDraft(d)}><strong>{d.message.subject}</strong><span>To: {d.message.to || "No recipients"} · {accounts.find(a=>a.id===d.account_id)?.email}</span></button>):threads.map(t=><div className={"mail-thread-row"+(t.unread?" unread":"")+(selected?.id===t.id&&selected.account_id===t.account_id?" selected":"")} key={`${t.account_id}|${t.id}`}><input type="checkbox" aria-label={`Select ${t.subject}`} checked={checks.has(`${t.account_id}|${t.id}`)} onChange={e=>setChecks(old=>{const next=new Set(old);e.target.checked?next.add(`${t.account_id}|${t.id}`):next.delete(`${t.account_id}|${t.id}`);return next;})}/><button className="mail-thread" onClick={()=>open(t)}><span className="mail-thread-meta"><span>{t.from}</span><time>{new Date(t.date).toLocaleDateString("en-AU",{day:"numeric",month:"short"})}</time></span><strong>{t.subject}{t.count>1?` (${t.count})`:""}</strong><span className="mail-snippet">{t.snippet}</span>{!account && <small className="mail-account-tag" title={accounts.find(a=>a.id===t.account_id)?.email}>{accounts.find(a=>a.id===t.account_id)?.email}</small>}</button><button className="icon-button" aria-label={t.starred?"Unstar":"Star"} onClick={()=>act(t.starred?"unstar":"star",t)}><Star size={16} fill={t.starred?"currentColor":"none"}/></button></div>)}
    {!busy && !threads.length && folder!=="drafts"&&folder!=="outbox"&&<div className="empty"><Inbox size={26}/><h2>{search?"No matching mail":"You’re up to date"}</h2><p>{search?"Try a different search.":"No messages in this view."}</p></div>}
    {Object.values(pages).some(Boolean) && folder!=="outbox"&&<button className="button" onClick={()=>load(true)} disabled={busy}>Load older messages</button>}
    </div>
   </section>
   {selected ? <section className="mail-reader" aria-label="Conversation"><div className="mail-actions"><button className="icon-button" aria-label="Back to messages" onClick={()=>{readerVersion.current++;setSelected(null);}}><ArrowLeft size={18}/></button><button onClick={()=>act("archive",selected)}>Archive</button><details className="item-actions"><summary>More</summary><div className="item-actions-panel"><button onClick={()=>act("unread",selected)}>Mark unread</button><button onClick={()=>act("trash",selected)}>Bin</button>{folder==="in:trash"?<button onClick={()=>act("restore",selected)}>Restore to Inbox</button>:folder==="in:spam"?<button onClick={()=>act("not_spam",selected)}>Not spam</button>:<button onClick={()=>act("spam",selected)}>Spam</button>}{labels.length>0 && <select aria-label="Add label" value="" onChange={e=>{if(e.target.value) void act("label",selected,e.target.value);}}><option value="">Add label</option>{labels.map(l=><option key={l.id} value={l.id}>{l.name}</option>)}</select>}</div></details></div><div className="mail-reader-scroll" key={`${selected.account_id}|${selected.id}`}><h2>{selected.subject}</h2><p className="fine-print">{accounts.find(a=>a.id===selected.account_id)?.email}</p>{!messages.length?<p role="status">Opening conversation…</p>:messages.map(m=><article className="mail-message" key={m.id}><header><strong>{m.from}</strong><time>{new Date(m.date).toLocaleString("en-AU")}</time><p>To: {m.to}{m.cc?` · Cc: ${m.cc}`:""}</p></header>{m.html?<MailHTMLBody html={m.html} from={m.from}/>:<div className="mail-text">{m.text || "This message has no text content."}</div>}{m.attachments.length>0 && <div className="mail-attachments">{m.attachments.map(a=><a className="button small" key={a.id} href={`/api/mail?${new URLSearchParams({account:selected.account_id,message:m.id,attachment:a.id,filename:a.name})}`}><Paperclip size={15}/>{a.name}</a>)}</div>}<div className="mail-actions"><button className="button" onClick={()=>compose(m)}>Reply</button><button className="button" onClick={()=>compose(m,true)}>Reply all</button><button className="button" onClick={()=>compose(m,false,true)}>Forward</button><button className="text-link" onClick={async()=>{try{const r=await fetch("/api/sessions",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({document:{session:{id:crypto.randomUUID(),title:m.subject,startedAt:new Date().toISOString(),endedAt:new Date().toISOString(),state:"noted",attendees:[],speakers:[],engine:"Notes",segmentCount:0,duration:0,noteSource:"You"},transcript:[],bullets:[],note:`From: ${m.from}\n\n${m.text}`},expectedVersion:0})});const b=await r.json();if(!r.ok) throw new Error(b.error);location.assign(`/notes?note=${b.id}`);}catch(e){setError((e as Error).message);}}}>Create note</button></div></article>)}</div></section>:<section className="mail-reader mail-reader-empty" aria-label="Conversation"><div className="empty"><Mail size={28}/><h2>Select a message</h2><p>Choose a conversation to read it here.</p></div></section>}
  </div>}
  {preferencesOpen && <MailSignatures accounts={accounts} onClose={()=>setPreferencesOpen(false)} onSaved={()=>{setPreferencesOpen(false);void loadAccounts();}}/>}
  {composer && <MailComposer initial={composer} accounts={accounts} userID={userID} onClose={()=>{setComposer(null);void load();}} onSent={()=>{setComposer(null);setNotice("Message queued. Undo send is available in Outbox until delivery starts.");setFolder("outbox");void loadAccounts();}}/>}
 </Shell>;
}
function MailHTMLBody({html,from}:{html:string;from:string}) {
 const frame=useRef<HTMLIFrameElement>(null),[height,setHeight]=useState(320);
 useEffect(()=>{
  const element=frame.current;if(!element)return;
  let observer:ResizeObserver|undefined;
  const measure=()=>{const body=element.contentDocument?.body;if(body)setHeight(Math.min(20000,Math.max(40,body.scrollHeight)));};
  const loaded=()=>{observer?.disconnect();const body=element.contentDocument?.body;if(body){observer=new ResizeObserver(measure);observer.observe(body);}measure();};
  element.addEventListener("load",loaded);loaded();
  return()=>{element.removeEventListener("load",loaded);observer?.disconnect();};
 },[html]);
 return <iframe ref={frame} title={`Message from ${from}`} style={{height}} sandbox="allow-same-origin allow-popups allow-popups-to-escape-sandbox" referrerPolicy="no-referrer" srcDoc={`<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'"><style>:root{color-scheme:light dark}body{margin:0;font:15px system-ui;color:CanvasText;background:Canvas;line-height:1.6;overflow-wrap:anywhere}table{max-width:100%}blockquote{border-left:1px solid GrayText;margin-left:0;padding-left:1em;color:GrayText}</style>${html}`}/>;
}

function MailComposer({initial,accounts,userID,onClose,onSent}:{initial:LocalDraft;accounts:Account[];userID:string;onClose:()=>void;onSent:()=>void}) {
 const [value,setValue]=useState(initial),[to,setTo]=useState(initial.to.join(", ")),[cc,setCc]=useState(initial.cc.join(", ")),[bcc,setBcc]=useState(initial.bcc.join(", ")),[error,setError]=useState(""),[status,setStatus]=useState(""),[busy,setBusy]=useState(false),[scheduled,setScheduled]=useState(initial.scheduled || ""),[attaching,setAttaching]=useState(false);
 const edits=useRef(new DraftEdits(Boolean(initial.local_key)));
 const draftID=useRef(initial.id),providerRevision=useRef(initial.revision),savedOK=useRef(true),localSaved=useRef(true),saving=useRef(Promise.resolve()),operationID=useRef(crypto.randomUUID());
 const storageKey=useRef(initial.local_key || `voice-notes:draft:${userID}:${initial.connection_id}:${initial.id || operationID.current}`).current;
 const edit=()=>edits.current.edit();
 const message=()=>({...value,scheduled,id:draftID.current,revision:providerRevision.current,to:addresses(to).map(emailAddress),cc:addresses(cc).map(emailAddress),bcc:addresses(bcc).map(emailAddress)});
 useEffect(()=>{if(initial.id || initial.subject || initial.text) return;try{const cached=localStorage.getItem(storageKey);if(cached){const v=JSON.parse(cached);setValue(v);setTo(v.to.join(", "));setCc(v.cc.join(", "));setBcc(v.bcc.join(", "));draftID.current=v.id;providerRevision.current=v.revision;setStatus("Recovered your local draft.");}}catch{}},[]);
 const save=useCallback(async()=>{
  if(!edits.current.dirty){await saving.current;return;}
  const v=message(),run=edits.current.capture();
  try {localStorage.setItem(storageKey,JSON.stringify(v));localSaved.current=true;}catch{localSaved.current=false;}
  saving.current=saving.current.catch(()=>{}).then(async()=>{try {setStatus("Saving draft…");const b=await api({}, {action:"draft",message:{...v,id:draftID.current,revision:providerRevision.current}});draftID.current=b.id;providerRevision.current=b.revision;savedOK.current=true;if(edits.current.acknowledge(run)) {setError("");setStatus("Draft saved in Gmail");try{localStorage.removeItem(storageKey);}catch{}}}catch(e){savedOK.current=false;setStatus(localSaved.current?"Saved on this device · Gmail unavailable":"Unable to save this draft · keep this window open");setError((localSaved.current?"":"This device could not save your draft. Keep this window open. ")+(e as Error).message);}});
  await saving.current;
 },[value,to,cc,bcc,scheduled]);
 useEffect(()=>{const timer=setTimeout(()=>void save(),1200);return()=>clearTimeout(timer);},[save]);
 async function send() {
  setBusy(true);setError("");try {await save();if(!savedOK.current) throw new Error("Resolve the draft saving error before sending. Your draft remains on this device.");await api({}, {action:"send",operation_id:operationID.current,message:message(),...(scheduled?{due_at:new Date(scheduled).toISOString()}:{})});localStorage.removeItem(storageKey);onSent();}catch(e){setError((e as Error).message);}finally{setBusy(false);}
 }
 async function attach(files:FileList|null) {
  const chosen=Array.from(files || []);
  if(value.attachments.length+chosen.length>20){setError("Use at most 20 attachments.");return;}
  setAttaching(true);
  try {
   let total=value.attachments.reduce((n,a)=>n+a.data.length*0.75,0);
   for(const file of chosen) {
    if(file.size+total>18000000){setError("Attachments must total less than 18 MB.");return;}
    total+=file.size;
    const data=await new Promise<string>((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(String(reader.result).split(",")[1]);reader.onerror=reject;reader.readAsDataURL(file);});
    edit();setValue(v=>({...v,attachments:[...v.attachments,{name:file.name,type:file.type || "application/octet-stream",data}]}));
   }
  } catch {setError("This attachment could not be read. Choose the file again.");}
  finally {setAttaching(false);}
 }

 return <Dialog label="Compose message" onClose={()=>{if(!busy && !attaching) void save().then(()=>{if(savedOK.current || localSaved.current) onClose();});}}><section className="mail-composer" onChangeCapture={edit}><header><h2>New message</h2><button className="icon-button" aria-label="Save draft and close" disabled={busy || attaching} onClick={()=>save().then(()=>{if(savedOK.current || localSaved.current) onClose();})}><X size={18}/></button></header>{error && <p className="notice" role="alert">{error}</p>}<label className="field"><span>From</span><select value={value.connection_id} disabled onChange={e=>setValue(v=>({...v,connection_id:e.target.value}))}>{accounts.map(a=><option key={a.id} value={a.id}>{a.email}</option>)}</select></label><label className="field"><span>To</span><input autoFocus disabled={busy} value={to} onChange={e=>setTo(e.target.value)}/></label><div className="form-grid"><label className="field"><span>Cc</span><input disabled={busy} value={cc} onChange={e=>setCc(e.target.value)}/></label><label className="field"><span>Bcc</span><input disabled={busy} value={bcc} onChange={e=>setBcc(e.target.value)}/></label></div><label className="field"><span>Subject</span><input disabled={busy} value={value.subject} onChange={e=>setValue(v=>({...v,subject:e.target.value}))}/></label><label className="field"><span>Message</span><textarea rows={12} disabled={busy || Boolean(value.html)} value={value.text || (value.html?"Formatted Gmail draft preserved. Switch to plain text to edit the message body.":"")} onChange={e=>setValue(v=>({...v,text:e.target.value}))}/></label>{value.html && <p className="notice">The original formatted body is preserved. <button className="text-link" disabled={busy || attaching} onClick={()=>{if(confirm("Convert this formatted draft to plain text? Its layout and inline images will be removed.")){edit();setValue(v=>({...v,html:undefined,text:v.text}));}}}>Switch to plain text…</button></p>}
 {error.includes("changed in Gmail") && <button className="button" disabled={busy || attaching} onClick={()=>{edit();draftID.current=undefined;providerRevision.current=undefined;operationID.current=crypto.randomUUID();setError("");setValue(v=>({...v,id:undefined,revision:undefined}));}}>Keep my edits as a new draft</button>}
 <div className="mail-attachments">{value.attachments.map((a,i)=><button key={`${a.name}-${i}`} className="button small" disabled={busy || attaching} onClick={()=>{edit();setValue(v=>({...v,attachments:v.attachments.filter((_,n)=>n!==i)}));}}>{a.name}<X size={14}/></button>)}</div><label className="field"><span>Attachments</span><input type="file" disabled={busy || attaching} multiple onChange={e=>void attach(e.target.files)}/></label><label className="field"><span>Send later (optional)</span><input type="datetime-local" disabled={busy} value={scheduled} onChange={e=>setScheduled(e.target.value)}/></label><footer><span role="status">{status}</span><button className="button primary" disabled={busy || attaching} onClick={()=>void send()}><Send size={16}/>{busy?"Queueing…":scheduled?"Schedule send":"Send"}</button></footer></section></Dialog>;
}

function MailSignatures({accounts,onClose,onSaved}:{accounts:Account[];onClose:()=>void;onSaved:()=>void}) {
 const [account,setAccount]=useState(accounts[0]?.id || ""),[signature,setSignature]=useState(accounts[0]?.signature || ""),[busy,setBusy]=useState(false),[error,setError]=useState("");
 return <Dialog label="Email signatures" onClose={()=>{if(!busy)onClose();}}><form className="mail-composer" onSubmit={async e=>{e.preventDefault();setBusy(true);setError("");try{await api({}, {action:"preferences",account,signature});onSaved();}catch(error){setError((error as Error).message);}finally{setBusy(false);}}}><header><h2>Email signatures</h2><button type="button" className="icon-button" aria-label="Close signatures" disabled={busy} onClick={onClose}><X size={18}/></button></header>{error&&<p className="notice" role="alert">{error}</p>}<label className="field"><span>Gmail account</span><select value={account} disabled={busy} onChange={e=>{setAccount(e.target.value);setSignature(accounts.find(a=>a.id===e.target.value)?.signature || "");}}>{accounts.map(a=><option key={a.id} value={a.id}>{a.email}</option>)}</select></label><label className="field"><span>Signature</span><textarea rows={8} maxLength={5000} value={signature} disabled={busy} onChange={e=>setSignature(e.target.value)}/></label><p className="muted">Added to new messages and replies from this account on the web and Mac. Existing drafts keep their original text.</p><button className="button primary" disabled={busy||!account}>{busy?"Saving…":"Save signature"}</button></form></Dialog>;
}
