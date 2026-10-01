"use client";
import {useEffect,useRef,useState} from "react";
import {Briefcase,Mail,User,X} from "lucide-react";
import {Dialog} from "./dialog";
import {mailboxColour,mailboxIcon,mailboxColours,mailboxIcons,type MailIdentity,type MailboxColour,type MailboxIcon} from "@/lib/mail/identity";
import type {MailRequest} from "./mail-workspace";
export type MailAccountPreference=MailIdentity & {email:string;signature?:string};
export function MailboxAvatar({account}:{account:MailIdentity}) {
 const icon=mailboxIcon(account),Symbol=icon==="work"?Briefcase:icon==="personal"?User:Mail;
 return icon==="none"?null:<span className={`mail-account-avatar mailbox-colour-${mailboxColour(account)}`} aria-hidden="true">{icon==="initials"?(account.email?.[0] || "?").toUpperCase():<Symbol size={14}/>}</span>;
}
export function MailboxBadge({account}:{account:MailIdentity}) {
 return <span className={`mail-account-tag mailbox-colour-${mailboxColour(account)}`} title={account.email || "Mailbox"}><MailboxAvatar account={account}/><span>{account.email || "Mailbox"}</span></span>;
}
type Preferences={signature:string;identity_colour:MailboxColour|null;identity_icon:MailboxIcon|null};
const values=(a:MailAccountPreference):Preferences=>({signature:a.signature || "",identity_colour:a.identity_colour ?? null,identity_icon:a.identity_icon ?? null});
const equal=(a:Preferences,b:Preferences)=>a.signature===b.signature&&a.identity_colour===b.identity_colour&&a.identity_icon===b.identity_icon;
const title=(value:string)=>value[0].toUpperCase()+value.slice(1);
export function MailPreferences({request,accounts:availableAccounts,initialAccount,onClose,onSaved,previewMode}:{request:MailRequest;accounts:MailAccountPreference[];initialAccount:string;onClose:()=>void;onSaved:()=>void;previewMode:boolean}) {
 const [accounts]=useState(availableAccounts);
 const [account,setAccount]=useState(initialAccount || accounts[0]?.id || "");
 const [saved,setSaved]=useState(()=>Object.fromEntries(accounts.map(a=>[a.id,values(a)]))),[edits,setEdits]=useState(saved);
 const [busy,setBusy]=useState(false),[error,setError]=useState(""),[notice,setNotice]=useState(""),[discard,setDiscard]=useState(false);
 const saving=useRef(false),active=useRef(true);
 useEffect(()=>{active.current=true;return()=>{active.current=false;};},[]);
 const current=edits[account],owner=accounts.find(a=>a.id===account);
 const dirty=accounts.some(a=>!equal(edits[a.id],saved[a.id]));
 const change=(patch:Partial<Preferences>)=>{setEdits(old=>({...old,[account]:{...old[account],...patch}}));setNotice("");setDiscard(false);};
 const close=()=>{if(!saving.current){if(dirty)setDiscard(true);else onClose();}};
 return <Dialog label="Mailbox preferences" onClose={close}><form className="mail-composer mail-preferences" onSubmit={async event=>{
  event.preventDefault();if(saving.current||!current||!owner)return;
  const target=account,patch={...current};saving.current=true;setBusy(true);setError("");setNotice("");
  try {await request({}, {action:"preferences",account:target,...patch});if(active.current){setSaved(old=>({...old,[target]:patch}));setNotice(`Saved preferences for ${owner.email}.`);onSaved();}}
  catch(error){if(active.current)setError(error instanceof Error?error.message:"Mailbox preferences could not save. Your edits are kept here.");}
  finally {saving.current=false;if(active.current)setBusy(false);}
 }}><header><h2>Mailbox preferences</h2><button type="button" className="icon-button" aria-label="Close mailbox preferences" disabled={busy} onClick={close}><X size={18}/></button></header>
 {error&&<p className="notice" role="alert">{error}</p>}{notice&&<p className="notice" role="status">{notice}</p>}
 {discard&&<div className="notice" role="alert"><p>You have unsaved preferences. Keep editing or discard these changes.</p><button className="button" type="button" onClick={()=>setDiscard(false)}>Keep editing</button> <button className="button" type="button" onClick={onClose}>Discard unsaved changes</button></div>}
 <label className="field"><span>Gmail account</span><select value={account} disabled={busy} onChange={event=>{setAccount(event.target.value);setNotice("");setError("");}}>{accounts.map(a=><option key={a.id} value={a.id}>{a.email}</option>)}</select></label>
 {current&&owner&&<><div className="mail-preferences-preview"><MailboxBadge account={{...owner,...current}}/><p className="fine-print">Your address stays visible. Appearance never changes the sender or permissions.</p></div>
 <div className="mail-identity-fields"><label className="field"><span>Colour</span><select aria-label="Mailbox colour" disabled={busy} value={current.identity_colour || ""} onChange={event=>change({identity_colour:(event.target.value || null) as MailboxColour|null})}><option value="">Automatic</option>{mailboxColours.map(colour=><option key={colour} value={colour}>{title(colour)}</option>)}</select></label>
 <label className="field"><span>Icon</span><select aria-label="Mailbox icon" disabled={busy} value={current.identity_icon || "initials"} onChange={event=>change({identity_icon:event.target.value as MailboxIcon})}>{mailboxIcons.map(icon=><option key={icon} value={icon}>{title(icon)}</option>)}</select></label></div>
 <label className="field"><span>Signature</span><textarea rows={5} maxLength={5000} disabled={busy} value={current.signature} onChange={event=>change({signature:event.target.value})}/></label></>}
 <p className="muted">{previewMode?"Synthetic preferences are saved in this browser only. No connected account is changed.":"Appearance and signatures are shared with the Mac app. Existing drafts keep their original text."} Built-in icons load without a logo service.</p>
 <div className="mail-actions"><button className="button" type="button" disabled={busy} onClick={close}>Done</button><button className="button primary" disabled={busy||!current||equal(current,saved[account])}>{busy?"Saving…":"Save this mailbox"}</button></div>
 </form></Dialog>;
}
