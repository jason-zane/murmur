"use client";
import { useEffect,useRef,useState } from "react";
import { CalendarDays,X,ArrowLeft,ShieldCheck } from "lucide-react";
import { Dialog } from "./dialog";
import { InviteProposalStorage,acceptAvailability,availabilitySignature,editProposal,newProposal,proposalKey,proposalProblems,reviewProposal,type InviteSource,type InviteCalendar,type InviteCheck,type InviteFields,type InviteProposal } from "@/lib/invite-proposal";

export type InviteReviewSupport={calendars:InviteCalendar[];check:InviteCheck;evidence:Record<string,string>};
export function InviteProposalReview({source,userID,support,onClose}:{source:InviteSource;userID:string;support:InviteReviewSupport;onClose:()=>void}) {
  const [proposal,setProposal]=useState(()=>newProposal(source)),[ready,setReady]=useState(false),[storageError,setStorageError]=useState(""),[error,setError]=useState(""),[status,setStatus]=useState(""),[sourceChanged,setSourceChanged]=useState(false),[checking,setChecking]=useState(false),[approved,setApproved]=useState(false);
  const [exitWarning,setExitWarning]=useState(false);
  const title=useRef<HTMLInputElement|null>(null);
  const store=useRef<InviteProposalStorage|null>(null),current=useRef(proposal),run=useRef(0),abort=useRef<AbortController|null>(null);
  current.current=proposal;
  useEffect(()=>{if(ready)title.current?.focus();},[ready]);
  useEffect(()=>{
    let storage:Storage|undefined;try{storage=localStorage;}catch{}
    const port=new InviteProposalStorage(storage,proposalKey(userID,source));store.current=port;
    try {const loaded=port.load(source);setProposal(loaded.proposal);setSourceChanged(loaded.sourceChanged);setApproved(loaded.proposal.reviewed);if(loaded.sourceChanged)port.write(loaded.proposal);setStatus(loaded.proposal.reviewed?"Reviewed proposal restored · no event created":loaded.restored?"Local proposal restored":"Confirm details to keep a local proposal");}
    catch(e){setStorageError(e instanceof Error?e.message:"Saved proposal could not be read. Its data is preserved.");}
    setReady(true);
    return()=>{run.current++;abort.current?.abort();};
  },[userID,source]);
  function persist(next:InviteProposal) {
    current.current=next;setProposal(next);
    try{store.current?.write(next);setStorageError("");setStatus(next.reviewed?"Reviewed proposal saved in this browser · no event created":"Edits saved in this browser · no event created");}
    catch(e){setStorageError(e instanceof Error?e.message:"Edits could not be saved. Keep this review open.");setStatus("");}
  }
  function edit(patch:Partial<InviteFields>) {
    run.current++;abort.current?.abort();setChecking(false);setApproved(false);setError("");persist(editProposal(current.current,patch));
  }
  async function check() {
    const signature=availabilitySignature(proposal.fields),ticket=++run.current;
    abort.current?.abort();const controller=new AbortController();abort.current=controller;setChecking(true);setApproved(false);setError("");
    try {const result=await support.check(proposal.fields,controller.signal);if(ticket!==run.current||controller.signal.aborted)return;persist(acceptAvailability(current.current,signature,result,Date.now()));}
    catch(e){if(ticket===run.current&&!controller.signal.aborted)persist(acceptAvailability(current.current,signature,{status:"unavailable",detail:e instanceof Error?e.message:"Sample availability could not load."},Date.now()));}
    finally{if(ticket===run.current)setChecking(false);}
  }
  useEffect(()=>{if(!storageError)return;const protect=(event:BeforeUnloadEvent)=>{event.preventDefault();event.returnValue="";};window.addEventListener("beforeunload",protect);return()=>window.removeEventListener("beforeunload",protect);},[storageError]);
  function leave() {run.current++;abort.current?.abort();onClose();}
  function close() {if(storageError){setExitWarning(true);return;}leave();}
  const fields=proposal.fields,problems=proposalProblems(proposal,support.calendars),availability=proposal.availability;
  const checkStale=Boolean(availability&&(Date.now()-availability.checkedAt>600000||Date.now()<availability.checkedAt));
  const canReview=ready&&!checking&&!storageError&&!problems.length&&availability?.status==="clear"&&!checkStale;
  const accountOptions=[...new Map(support.calendars.map(c=>[c.accountID,c.accountEmail])).entries()];
  return <Dialog label="Review invitation proposal" onClose={close}><section className="invite-review">
    <header className="invite-review-heading"><div><span className="eyebrow"><CalendarDays size={15}/>Email to calendar</span><h2>Review invitation</h2><p>Sample proposal · edit and keep locally. No event or invitation is created.</p></div><button className="icon-button" aria-label="Close invitation review" onClick={close}><X size={18}/></button></header>
    <div className="invite-review-layout"><aside className="invite-source" aria-label="Invitation source"><h3>What the email says</h3><p><strong>{source.subject}</strong></p><p className="fine-print">{source.from}<br/>{source.mailbox}<br/>{new Date(source.sentAt).toLocaleString("en-AU")}</p><blockquote>{source.evidence}</blockquote><p className="fine-print">Tentative wording is evidence, not confirmation. Date, time zone, duration and attendees need your review.</p><details><summary>Read original sample email</summary><p className="mail-text">{source.text}</p></details>{sourceChanged&&<p className="notice" role="alert">The source changed. Your edits are retained; review and availability were reset.</p>}</aside>
    <form className="invite-fields" onSubmit={e=>{e.preventDefault();if(!canReview||!approved||proposal.reviewed)return;try{persist(reviewProposal(proposal,support.calendars,Date.now()));}catch(error){setError(error instanceof Error?error.message:"Review could not complete.");}}}>
      {storageError&&<p className="notice" role="alert">{storageError} <strong>Keep this review open. Closing may lose these edits.</strong></p>}{exitWarning&&<div className="notice" role="alert"><p>These edits have not been saved. Keep reviewing or close without them.</p><button type="button" className="button" onClick={()=>setExitWarning(false)}>Keep review open</button><button type="button" className="text-link" onClick={leave}>Close without saved edits</button></div>}{error&&<p className="notice" role="alert">{error}</p>}
      <label className="field"><span>Meeting title</span><input ref={title} disabled={!ready} value={fields.title} onChange={e=>edit({title:e.target.value})}/></label>
      <div className="form-grid"><label className="field"><span>Calendar account</span><select disabled={!ready} value={fields.accountID} onChange={e=>edit({accountID:e.target.value,calendarID:""})}>{accountOptions.map(([id,email])=><option key={id} value={id}>{email}</option>)}</select></label><label className="field"><span>Destination calendar</span><select disabled={!ready} value={fields.calendarID} onChange={e=>edit({calendarID:e.target.value})}><option value="">Choose a calendar</option>{support.calendars.filter(c=>c.accountID===fields.accountID).map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label></div>
      <div className="form-grid"><label className="field"><span>Starts</span><input disabled={!ready} type="datetime-local" value={fields.start} onInput={e=>edit({start:e.currentTarget.value})}/></label><label className="field"><span>Ends</span><input disabled={!ready} type="datetime-local" value={fields.end} onInput={e=>edit({end:e.currentTarget.value})}/></label></div>
      <label className="field"><span>Time zone</span><input disabled={!ready} list="invite-time-zones" placeholder="Confirm a time zone" value={fields.zone} onChange={e=>edit({zone:e.target.value})}/><datalist id="invite-time-zones">{["Australia/Sydney","Europe/London","America/New_York","America/Los_Angeles","UTC"].map(zone=><option key={zone} value={zone}/>)}</datalist></label>
      <label className="field"><span>Attendees to confirm</span><input disabled={!ready} value={fields.guests} placeholder="Email addresses, separated by commas" onChange={e=>edit({guests:e.target.value})}/></label>
      {problems.length>0&&<div className="invite-confirmations"><strong>Still to confirm</strong><ul>{problems.map(problem=><li key={problem}>{problem}</li>)}</ul></div>}
      <section className="invite-availability" aria-label="Sample availability"><h3>Availability</h3><p className="fine-print">Synthetic calendars only. Checks the chosen account’s sample busy times; attendee calendars are not checked.</p>{availability&&<p role={availability.status==="clear"?"status":"alert"}>{checkStale?"The sample check has expired. Check again.":availability.detail}</p>}<div className="form-actions"><button type="button" className="button" disabled={checking||!ready||problems.length>0} onClick={()=>void check()}>{checking?"Checking sample availability…":"Check sample availability"}</button>{checking&&<button type="button" className="text-link" onClick={()=>{run.current++;abort.current?.abort();setChecking(false);setStatus("Check cancelled · your edits are retained");}}>Cancel check</button>}</div></section>
      <label className="check"><input type="checkbox" checked={approved} disabled={!canReview||proposal.reviewed} onChange={e=>setApproved(e.target.checked)}/>I’ve checked the email, destination and meeting details.</label>
      <footer className="invite-review-footer"><span role="status">{status}</span><div className="form-actions"><button type="button" className="text-link" onClick={close}><ArrowLeft size={15}/>Back to email</button><button className="button primary" disabled={!canReview||!approved||proposal.reviewed}><ShieldCheck size={16}/>{proposal.reviewed?"Reviewed locally":"Mark reviewed locally"}</button></div></footer>
    </form></div>
  </section></Dialog>;
}
