"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { ArrowLeft, ArrowRight, RefreshCw, X, Save, AlertTriangle } from "lucide-react";
import { Shell } from "./shell";
import { WorkspaceList } from "./workspace-list";
import {
  acceptSuggestion, beginPreparation, completePreparation, editDraft, emptyState,
  failPreparation, FollowUpRequest, keepDraft, MockFollowUpProvider, PrototypeStorage,
  reviseSampleSource, sampleNote, saveLocalDraft, setReviewed, stopPreparation, undoSuggestion, unresolvedDetails,
  type PrototypeState,
} from "@/lib/follow-up/prototype";

const path = (noteID: string, review = false) => `/prototype/follow-up?note=${noteID}${review ? "&review=1" : ""}`;
export function FollowUpPrototype({noteID,reviewOpen}:{noteID:string;reviewOpen:boolean}) {
  const router=useRouter();
  const [query,setQuery]=useState(""), [tab,setTab]=useState("notes"), [sourceID,setSourceID]=useState<string|null>(null);
  const sourcePanel=useRef<HTMLDivElement>(null), selectedSource=useRef<HTMLElement>(null), lastTab=useRef("notes");
  const reviewHeading=useRef<HTMLHeadingElement>(null), openReviewLink=useRef<HTMLAnchorElement>(null), wasOpen=useRef(false);
  const [state,setState]=useState<PrototypeState>(emptyState);
  const stateRef=useRef(state), storage=useRef<PrototypeStorage|null>(null), request=useRef(new FollowUpRequest());
  const [hydrated,setHydrated]=useState(false), [storageIssue,setStorageIssue]=useState(""), [message,setMessage]=useState("");
  const [slow,setSlow]=useState(false), [outcome,setOutcome]=useState<"normal"|"failure"|"quota">("normal");
  const note=sampleNote(noteID,state.revisions[noteID] ?? 1), review=state.reviews[noteID];
  const saved=review ? state.drafts[review.id] : undefined;
  const stale=Boolean(review?.candidate && review.sourceRevision!==note.revision);
  const busy=review?.status==="preparing";
  const alreadySaved=Boolean(saved && review && saved.editVersion===review.editVersion && saved.sourceRevision===review.sourceRevision);
  const provider=new MockFollowUpProvider();

  function commit(next: PrototypeState, requirePersistence=false) {
    try {
      if(!storage.current)throw new Error("Browser storage is unavailable. Your edits are only held in this tab.");
      storage.current.write(next);setStorageIssue("");
    } catch(error) {
      setStorageIssue(error instanceof Error?error.message:"Your edits could not be kept in browser storage. Keep this tab open.");
      if(requirePersistence)return false;
    }
    stateRef.current=next;setState(next);return true;
  }
  useEffect(()=>{
    try {
      storage.current=new PrototypeStorage(localStorage);
      const loaded=storage.current.load();stateRef.current=loaded;setState(loaded);
      storage.current.write(loaded);
    } catch(error) { setStorageIssue(error instanceof Error?error.message:"Browser storage is unavailable. Keep this tab open to retain your edits."); }
    setHydrated(true);
  },[]);

  async function prepare() {
    const source=sampleNote(noteID,stateRef.current.revisions[noteID] ?? 1), id=crypto.randomUUID();
    commit(beginPreparation(stateRef.current,source,id));setMessage("");
    const result=await request.current.run(new MockFollowUpProvider(slow?5000:900,outcome),source);
    setOutcome("normal");
    if(!result)return;
    if("candidate" in result)commit(completePreparation(stateRef.current,source,id,result.candidate));
    else commit(failPreparation(stateRef.current,source.id,id,result.error,result.waiting));
  }
  function cancelPreparation() {
    request.current.cancel();commit(stopPreparation(stateRef.current,noteID));
  }
  useEffect(()=>{
    if(!hydrated)return;
    setMessage("");
    if(reviewOpen && !stateRef.current.reviews[noteID])void prepare();
    return ()=>{
      request.current.cancel();
      const interrupted=stopPreparation(stateRef.current,noteID);
      if(interrupted!==stateRef.current)commit(interrupted);
    };
  // Preparation runs once on entry. Field changes are deliberately absent: edits never trigger a provider.
  },[hydrated,noteID,reviewOpen,note.revision]);
  useEffect(()=>{
    if(!reviewOpen)return;
    const close=(event:KeyboardEvent)=>{if(event.key==="Escape"){event.preventDefault();router.replace(path(noteID));}};
    window.addEventListener("keydown",close);return ()=>window.removeEventListener("keydown",close);
  },[reviewOpen,noteID,router]);

  function edit(field: "recipient"|"subject"|"body", value: string) {
    commit(editDraft(stateRef.current,noteID,{[field]:value}));setMessage("");
  }
  function save() {
    try {
      const next=saveLocalDraft(stateRef.current,note,new Date().toISOString());
      if(commit(next,true))setMessage("Draft saved in this browser. Nothing has been sent or added to a mailbox.");
    } catch(error) { setMessage(error instanceof Error?error.message:"The local draft could not be saved. Your edits are kept."); }
  }
  useEffect(()=>{
    if(!hydrated)return;
    if(reviewOpen && !wasOpen.current)reviewHeading.current?.focus({preventScroll:true});
    if(!reviewOpen && wasOpen.current)openReviewLink.current?.focus({preventScroll:true});
    wasOpen.current=reviewOpen;
  },[hydrated,reviewOpen]);
  useEffect(()=>{setTab("notes");setSourceID(null);},[noteID]);
  useEffect(()=>{
    if(tab==="source"){const target=selectedSource.current || sourcePanel.current;target?.focus();target?.scrollIntoView({block:"nearest"});}
    else if(lastTab.current==="source" && reviewOpen)reviewHeading.current?.focus();
    lastTab.current=tab;
  },[tab,sourceID,reviewOpen]);
  function showSource(id:string) { setSourceID(id);setTab("source"); }
  const samples=[sampleNote("launch",state.revisions.launch??1),sampleNote("support")];
  const excerpt=note.evidence.find(span=>span.id===sourceID);

  const controls=<details className="prototype-controls">
    <summary>Synthetic test controls</summary>
    <label className="check"><input type="checkbox" checked={slow} onChange={event=>setSlow(event.target.checked)}/>Slow sample preparation</label>
    <label className="field"><span>Next sample preparation</span><select value={outcome} disabled={busy} onChange={event=>setOutcome(event.target.value as typeof outcome)}>
      <option value="normal">Normal</option><option value="failure">Simulated temporary failure</option><option value="quota">Simulated quota limit</option>
    </select></label>
    {noteID==="launch" && <button className="text-link" onClick={()=>commit(reviseSampleSource(stateRef.current,noteID,note.revision===1?2:1))}>{note.revision===1?"Use revised sample note":"Use original sample note"}</button>}
    <p className="fine-print">These controls change synthetic fixtures only. No provider or account is connected.</p>
  </details>;

  return <Shell email="prototype@example.com" layout="notes" activePath="/notes" previewMode>
    <div className={`review-workspace${reviewOpen ? " reviewing" : ""}`}>
      <WorkspaceList title="Notes" selected={noteID} query={query} onQuery={setQuery} onSelect={id=>router.push(path(id,reviewOpen))}
        items={samples.filter(sample=>`${sample.title} ${sample.people}`.toLowerCase().includes(query.toLowerCase())).map(sample=>({id:sample.id,title:sample.id==="launch"?"Pilot launch":"Support handover",meta:`Sample note · ${sample.people}`}))}>
        <p className="workspace-list-caption">Sample meetings</p>
        <div className="prototype-draft-count">Local drafts <span className="chip">{Object.keys(state.drafts).length}</span></div>
      </WorkspaceList>
      <article className="review-note-canvas" aria-label="Sample meeting note">
        <div className="review-note-toolbar"><Link className="text-link note-list-back" href={path(noteID)}><ArrowLeft size={16}/>Notes</Link><span className="fine-print">Fixed sample source · revision {note.revision}</span></div>
        <header className="review-note-header"><h1>{noteID==="launch"?"Pilot launch":"Support handover"}</h1><p>{note.people}</p></header>
        <div className="review-note-tabs" aria-label="Note views"><button aria-pressed={tab==="notes"} onClick={()=>setTab("notes")}>Notes</button><button aria-pressed={tab==="source"} onClick={()=>setTab("source")}>Source excerpts</button></div>
        {tab==="notes" ? <div className="review-note-body">
          {note.evidence.map((span,index)=><section key={span.id}><h2>{index===0?"Decision":index===1?"Details to confirm":"Follow-through"}</h2><p>{span.text} <button className="source-marker" aria-label={`Show source ${index+1}`} onClick={()=>showSource(span.id)}>[{index+1}]</button></p></section>)}
          <section className="review-note-next"><h2>Next step</h2><p>Review a follow-up beside this note. Confirm missing details before sharing.</p><Link ref={openReviewLink} className="button primary" href={path(noteID,true)}>{review?"Continue draft review":"Review follow-up"}<ArrowRight size={15}/></Link></section>
          <section className="review-note-quote"><h3>Key quote from the discussion</h3><strong>{note.evidence[1].speaker}</strong><blockquote>“{note.evidence[1].text}”</blockquote><button className="text-link" onClick={()=>showSource(note.evidence[1].id)}>View source 2 <ArrowRight size={14}/></button></section>
          <section className="review-note-reference-list" aria-label="Source references"><h3>Source references</h3>{note.evidence.map((span,index)=><button key={span.id} onClick={()=>showSource(span.id)}><span className="source-marker">{index+1}</span><span><span><strong>{span.speaker}:</strong> {span.text}</span><small>Fixed note excerpt · revision {note.revision}</small></span></button>)}</section>
        </div> : <div ref={sourcePanel} tabIndex={-1} className="review-note-body review-source-list">{reviewOpen && <button className="text-link source-back-review" onClick={()=>setTab("notes")}><ArrowLeft size={14}/>Back to draft review</button>}<p className="fine-print">Fixed excerpts from the synthetic note. There is no recording or live transcript in this preview.</p>{excerpt && <p className="review-selected-source" role="status">Showing the source you selected: {excerpt.speaker}.</p>}{note.evidence.map((span,index)=><section ref={sourceID===span.id?selectedSource:undefined} tabIndex={-1} key={span.id} id={`evidence-${span.id}`} className={sourceID===span.id?"selected-source":""}><h2>Source {index+1} · {span.speaker}</h2><blockquote>{span.text}</blockquote></section>)}</div>}
        {controls}
      </article>
      {reviewOpen && <aside className="review-inspector" aria-label="Follow-up draft review">
        <header className="review-inspector-header"><h2 ref={reviewHeading} tabIndex={-1}>Follow-up draft</h2><span className="chip">Local only</span><Link className="icon-button" href={path(noteID)} aria-label="Close draft review"><X size={18}/></Link></header>
        {storageIssue && <p className="notice" role="alert">{storageIssue} Keep this tab open to retain edits.</p>}
        {!hydrated || !review ? <p role="status">Opening local draft…</p> : <>
          {stale && <div className="review-warning" role="alert"><AlertTriangle size={17}/><div><strong>Source changed</strong><p>Prepare another sample and review the updated source before saving. Existing edits are kept.</p></div></div>}
          {review.error && <p className="notice" role="status">{review.error}</p>}
          {busy && <div className="prototype-progress" role="status"><span>Preparing a fixed sample…</span><button className="text-link" onClick={cancelPreparation}>Cancel preparation</button></div>}
          {review.staged && <section className="review-staged"><h3>Replacement ready for review</h3><p>Your edited draft is unchanged.</p><strong>{review.staged.fields.subject}</strong><p className="prototype-message-preview">{review.staged.fields.body}</p><div className="form-actions"><button className="button primary" disabled={busy} onClick={()=>commit(acceptSuggestion(stateRef.current,noteID))}>Use sample suggestion</button><button className="text-link" onClick={()=>commit(keepDraft(stateRef.current,noteID))}>Keep my draft</button></div></section>}
          <div className="review-draft-fields">
            <label className="field"><span>Recipient <small>Optional</small></span><input type="email" placeholder="Not provided" aria-describedby="prototype-recipient-help" autoComplete="off" value={review.fields.recipient} onChange={event=>edit("recipient",event.target.value)}/></label>
            <p className="fine-print" id="prototype-recipient-help">{review.fields.recipient ? "Entered by you; the source did not verify this address." : "Confirm who should receive this. You can keep it unaddressed."}</p>
            <label className="field"><span>Subject</span><input value={review.fields.subject} onChange={event=>edit("subject",event.target.value)}/></label>
            <label className="field"><span>Message</span><textarea rows={10} value={review.fields.body} onChange={event=>edit("body",event.target.value)}/></label>
          </div>
          {review.previous && <button className="text-link" disabled={busy} onClick={()=>commit(undoSuggestion(stateRef.current,noteID))}>Undo suggestion replacement</button>}
          <div className="review-warning"><AlertTriangle size={17}/><div><strong>Still to confirm</strong><ul>{(review.candidate?unresolvedDetails(review):["Recipient, owners and dates have not been checked."]).map(detail=><li key={detail}>{detail}</li>)}</ul></div></div>
          <label className="check review-approval"><input type="checkbox" checked={review.reviewed} disabled={!review.candidate || stale || busy} onChange={event=>commit(setReviewed(stateRef.current,noteID,event.target.checked))}/>I’ve checked the source and unresolved details.</label>
          <div className="review-draft-actions"><button className="button primary" disabled={!review.candidate || !review.reviewed || stale || busy || alreadySaved} onClick={save}><Save size={16}/>{alreadySaved?"Saved locally":saved?"Update local draft":"Save local draft"}</button><button className="button" disabled={busy} onClick={()=>void prepare()}><RefreshCw size={15}/>{review.candidate?"Prepare another sample":"Prepare sample draft"}</button></div>
          {message && <p className="notice" role="status">{message}</p>}
          <p className="review-draft-status">{alreadySaved?"This version is saved locally.":storageIssue?"Edits are held in this tab.":"Edits stay in this browser as you type."} Nothing is sent.</p>
          <details className="review-source-details"><summary>{stale?"Updated source to review":"Source details"} <span>{note.evidence.length} excerpts</span></summary><p className="fine-print">{stale?`Current source revision ${note.revision}; this draft uses revision ${review.sourceRevision}. These excerpts are not the basis of the older draft.`:"Evidence refers to the fixed suggestion. Your edits have not been independently verified."}</p>{note.evidence.map((span,index)=><div key={span.id}><button className="text-link" onClick={()=>showSource(span.id)}>Source {index+1} · {span.speaker}</button><blockquote>{span.text}</blockquote></div>)}</details>
          <details className="review-source-details"><summary>Draft context</summary><p>{provider.label} · {provider.funding}.</p><p className="fine-print">Recipe meeting-follow-up/v1. No email send or mailbox draft action is available.</p></details>
        </>}
      </aside>}
    </div>
  </Shell>;
}
