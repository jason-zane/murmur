"use client";
import { useEffect, useRef, useState } from "react";
import { ArrowLeft, RefreshCw, Save, X } from "lucide-react";
import { Dialog } from "./dialog";
import type { CloudSession } from "@/lib/documents";
import { followUpDocument, type FollowUpDocument } from "@/lib/follow-up/drafts";
import { FollowUpRecovery, FollowUpReviewSession, initialReviewState, recoveryKey, sourceExcerpts } from "@/lib/follow-up/review";

export function FollowUpReview({row,userID,request,onClose,onSource,previewMode}:{row:CloudSession;userID:string;request:typeof fetch;onClose:()=>void;onSource:(row:CloudSession)=>void;previewMode:boolean}) {
  const [state,setState]=useState(()=>initialReviewState(row)),[exitWarning,setExitWarning]=useState(false),[query,setQuery]=useState(""),[unknownText,setUnknownText]=useState("");
  useEffect(()=>{if(JSON.stringify(unknownText.split("\n").filter(value=>value.trim()))!==JSON.stringify(state.document.unknowns))setUnknownText(state.document.unknowns.join("\n"));},[state.document.unknowns,unknownText]);
  const session=useRef<FollowUpReviewSession|null>(null),subject=useRef<HTMLInputElement|null>(null),sourceCallback=useRef(onSource);
  sourceCallback.current=onSource;
  useEffect(()=>{
    let storage:Storage|undefined,tab="";
    try {storage=localStorage;tab=sessionStorage.getItem("concourse:review-tab") || crypto.randomUUID();sessionStorage.setItem("concourse:review-tab",tab);}catch{storage=undefined;}
    const current=new FollowUpReviewSession(row,new FollowUpRecovery(storage,recoveryKey(userID,row.id,tab)),request,setState,value=>sourceCallback.current(value));
    session.current=current;void current.load();
    return()=>{current.dispose();session.current=null;};
  },[row.id,userID,request]);
  useEffect(()=>{if(state.ready)subject.current?.focus({preventScroll:true});},[state.ready]);
  const dirty=session.current?.dirty ?? false,stale=state.document.sourceVersion!==state.source.version;
  const disabled=!state.ready || state.saving || state.loading || state.denied;
  const validReview=state.connected && !state.conflict && followUpDocument.safeParse({...state.document,reviewed:true}).success && !stale;
  useEffect(()=>{
    if(!state.storageError || !dirty)return;
    const guard=(event:BeforeUnloadEvent)=>{event.preventDefault();event.returnValue="";};window.addEventListener("beforeunload",guard);return()=>window.removeEventListener("beforeunload",guard);
  },[state.storageError,dirty]);
  function close(force=false) { if(!force && state.storageError && dirty){setExitWarning(true);return;}session.current?.dispose();onClose(); }
  function edit(patch:Partial<FollowUpDocument>) { session.current?.edit({...state.document,...patch}); }
  function fields(patch:Partial<FollowUpDocument["fields"]>) { edit({fields:{...state.document.fields,...patch}}); }
  const excerpts=sourceExcerpts(state.source).filter(item=>item.text.toLowerCase().includes(query.toLowerCase()));
  const selected=(item:FollowUpDocument["evidence"][number])=>state.document.evidence.some(value=>JSON.stringify(value)===JSON.stringify(item));
  return <Dialog label="Review meeting follow-up" onClose={()=>close()}><section className="follow-up-review invite-review">
    <header className="invite-review-heading"><div><span className="eyebrow">Meeting to follow-up</span><h2>Review follow-up</h2><p>{previewMode?"Synthetic workspace · saved copies stay in this browser.":"Save a draft in Concourse."} No AI generation, mailbox draft or email sending.</p></div><button className="icon-button" aria-label="Close follow-up review" onClick={()=>close()}><X size={18}/></button></header>
    <div className="invite-review-layout"><aside className="invite-source" aria-label="Follow-up source"><h3>{state.source.title}</h3><p className="fine-print">Current note · version {state.source.version}<br/>Draft evidence · version {state.document.sourceVersion}</p>
      {stale&&<div className="notice" role="alert"><p>The note changed. Your wording is retained, but its evidence and approval are out of date.</p><button className="button small" disabled={disabled} onClick={()=>session.current?.useCurrentSource()}>Review current source</button><p className="fine-print">Keeps your wording and clears old evidence so you can select current excerpts.</p></div>}
      {state.document.evidence.length>0&&<details className="follow-up-selected-evidence"><summary>{stale?"Earlier evidence":"Selected evidence"} · {state.document.evidence.length}</summary>{state.document.evidence.map((item,i)=><blockquote key={i}>{item.text}</blockquote>)}</details>}
      <label className="field"><span>Find source evidence</span><input value={query} onChange={event=>setQuery(event.target.value)} placeholder="Search this note and transcript"/></label>
      <p className="fine-print">Choose exact excerpts to review beside your wording. A matching excerpt does not prove every claim in your draft.</p>
      <div className="follow-up-excerpts">{excerpts.map((item,i)=><label className="follow-up-excerpt" key={`${item.kind}:${item.id}:${i}`}><input type="checkbox" checked={!stale&&selected(item)} disabled={disabled||stale||(!selected(item)&&state.document.evidence.length>=30)} onChange={event=>edit({evidence:event.target.checked?[...state.document.evidence,item]:state.document.evidence.filter(value=>JSON.stringify(value)!==JSON.stringify(item))})}/><span><small>{item.kind==="note"?"Note excerpt":item.kind==="transcript"?"Transcript excerpt":"Captured bullet"}{item.text.length===2000?" · first 2,000 characters":""}</small><span>{item.text}</span></span></label>)}</div>
      {!excerpts.length&&<p className="fine-print">{query?"No excerpts match. Try a different search.":"No source text yet. Write and save the note before reviewing a follow-up."}</p>}
    </aside><form className="invite-fields follow-up-fields" onSubmit={event=>{event.preventDefault();void session.current?.save();}}>
      {state.error&&<p className="notice" role="alert">{state.error}</p>}
      {state.storageError&&<p className="notice" role="alert">{state.storageError} {dirty?"These edits are not safely recovered; keep this review open until saved.":"The original recovery data has not been replaced."}</p>}
      {exitWarning&&<div className="notice" role="alert"><p>Your unsaved edits cannot be recovered in this browser.</p><div className="form-actions"><button type="button" className="button" onClick={()=>setExitWarning(false)}>Keep review open</button><button type="button" className="text-link" onClick={()=>close(true)}>Close without recovery</button></div></div>}
      {!state.ready&&<p role="status">Opening saved follow-up…</p>}
      <label className="field"><span>Recipient to confirm</span><input disabled={disabled} maxLength={254} value={state.document.fields.recipient} onChange={event=>fields({recipient:event.target.value})} placeholder="Email address · never guessed"/></label>
      <label className="field"><span>Subject</span><input ref={subject} disabled={disabled} maxLength={200} value={state.document.fields.subject} onChange={event=>fields({subject:event.target.value})}/></label>
      <label className="field"><span>Draft wording</span><textarea disabled={disabled} rows={10} maxLength={10000} value={state.document.fields.body} onChange={event=>fields({body:event.target.value})} placeholder="Write the follow-up you want to review."/></label>
      <div className="form-actions"><button type="button" className="text-link" disabled={disabled||stale||!state.document.evidence.length} onClick={()=>session.current?.stageExcerpts()}>Use selected excerpts</button>{state.previous&&<button type="button" className="text-link" disabled={disabled} onClick={()=>session.current?.undo()}>Restore earlier edits</button>}</div>
      {state.staged!==null&&<section className="follow-up-staged"><h3>Review replacement wording</h3><p className="fine-print">Exact selected excerpts, without AI. Your existing wording stays until you choose.</p><p className="mail-text">{state.staged}</p><div className="form-actions"><button type="button" className="button small" disabled={disabled} onClick={()=>session.current?.acceptStaged()}>Replace wording</button><button type="button" className="text-link" onClick={()=>session.current?.keepWording()}>Keep my wording</button></div></section>}
      <label className="field"><span>Details still to confirm</span><textarea disabled={disabled} rows={3} maxLength={10000} value={unknownText} onChange={event=>{setUnknownText(event.target.value);edit({unknowns:event.target.value.split("\n").filter(value=>value.trim())});}} placeholder="One per line, such as a missing owner or tentative date."/></label><p className="fine-print">Keep unresolved details here until you have confirmed them. Incomplete work can still be saved. Up to 20 details, 500 characters each.</p>
      {state.conflict&&<section className="follow-up-conflict" aria-label="Saved draft conflict"><h3>Choose which wording to keep</h3><p>Your edits remain in this tab. A different copy is saved at version {state.conflict.draft?.version || 0}. Saving is paused until you choose.</p><div className="follow-up-comparison"><div><strong>Your edits</strong><p>{state.document.fields.recipient || "Recipient missing"}</p><p>{state.document.fields.subject}</p><p className="mail-text">{state.document.fields.body || "No wording yet"}</p></div><div><strong>Latest saved copy</strong><p>{state.conflict.draft?.document.fields.recipient || "Recipient missing"}</p><p>{state.conflict.draft?.document.fields.subject}</p><p className="mail-text">{state.conflict.draft?.document.fields.body || "No wording yet"}</p></div></div><div className="form-actions"><button type="button" className="button small" disabled={disabled} onClick={()=>session.current?.resolveConflict("mine")}>Keep my edits</button><button type="button" className="button small" disabled={disabled} onClick={()=>session.current?.resolveConflict("cloud")}>Use saved wording</button></div><p className="fine-print">Neither choice sends or immediately saves anything. Review again before saving.</p></section>}
      <label className="check"><input type="checkbox" checked={state.document.reviewed} disabled={disabled||!validReview||Boolean(state.conflict)} onChange={event=>session.current?.setReviewed(event.target.checked)}/>I’ve checked the current source, recipient, wording and unresolved details.</label>
      {!state.connected&&state.ready&&<p className="fine-print">Refresh the saved copy to check access and the current note before saving or marking reviewed.</p>}
      {!validReview&&state.connected&&<p className="fine-print">To mark reviewed: confirm a valid recipient, subject, wording and at least one current source excerpt; resolve the listed missing details.</p>}
      <footer className="invite-review-footer"><span role="status">{state.loading?"Refreshing saved copy…":previewMode?state.status.replaceAll("in Concourse","in the browser’s synthetic workspace"):state.status}</span><div className="form-actions"><button type="button" className="text-link" onClick={()=>close()}><ArrowLeft size={15}/>Back to note</button><button type="button" className="button" disabled={state.saving||state.loading} onClick={()=>void session.current?.load()}><RefreshCw size={15}/>Refresh saved copy</button>{state.saving?<button type="button" className="button" onClick={()=>session.current?.cancelSave()}>Cancel save</button>:<button className="button primary" disabled={disabled||!state.connected||Boolean(state.conflict)||stale||!dirty}><Save size={16}/>{state.document.reviewed?"Save reviewed draft":"Save unfinished draft"}</button>}</div></footer>
    </form></div>
  </section></Dialog>;
}
