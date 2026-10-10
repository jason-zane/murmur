import { z } from "zod";

export const RECIPE = "meeting-follow-up/v1" as const;
export const STORAGE_KEY = "concourse:synthetic-follow-up:v1";
export type Evidence = { id: string; speaker: string; text: string };
export type SampleNote = { id: string; revision: number; title: string; people: string; evidence: Evidence[]; subject: string; body: string; unknowns: string[] };

/** Fixed synthetic fixtures only. This module never loads a meeting or mailbox. */
export function sampleNote(id: string, revision = 1): SampleNote {
  if (id === "support") return {
    id, revision: 1, title: "Support handover", people: "Sam Ito · Priya Nair",
    evidence: [
      { id: "support-1", speaker: "Priya", text: "We agreed to review the support queue together each week." },
      { id: "support-2", speaker: "Sam", text: "I’ll collect the recurring questions for the first review." },
      { id: "support-3", speaker: "Priya", text: "Let’s confirm the first review date and who should receive the handover." },
    ],
    subject: "Support handover: next steps",
    body: "Hi,\n\nWe agreed to review the support queue together each week. Sam will collect the recurring questions for the first review.\n\nCould we confirm the first review date and who should receive the handover?\n\nThanks",
    unknowns: ["The first review date was not agreed."],
  };
  const revised = revision === 2;
  return {
    id: "launch", revision: revised ? 2 : 1, title: revised ? "Pilot launch · revised decisions" : "Pilot launch · next steps", people: "Sam Ito · Priya Nair",
    evidence: [
      { id: "launch-1", speaker: "Priya", text: revised ? "The pilot is paused until the accessibility review is complete." : "We agreed to start with a small pilot before a wider launch." },
      { id: "launch-2", speaker: "Sam", text: revised ? "We still need to confirm who owns the review and its completion date." : "The checklist needs an owner. Could we aim for next Friday? That date isn’t confirmed." },
      { id: "launch-3", speaker: "Priya", text: "Please share the agreed next steps after we confirm who should receive them." },
    ],
    subject: revised ? "Pilot launch: revised next steps" : "Pilot launch: next steps",
    body: revised ? "Hi,\n\nThe pilot is paused until the accessibility review is complete.\n\nCould we confirm the review owner, completion date and who should receive the next steps?\n\nThanks" : "Hi,\n\nWe agreed to start with a small pilot before a wider launch. The checklist still needs an owner.\n\nCould we confirm the checklist owner and target date? Next Friday was suggested, but was not agreed. Please also confirm who should receive the next steps.\n\nThanks",
    unknowns: revised ? ["The accessibility review owner is missing.", "The completion date was not agreed."] : ["The checklist owner is missing.", "“Next Friday” is tentative; no date or time zone was confirmed."],
  };
}

const fieldsSchema = z.object({ recipient: z.string(), subject: z.string(), body: z.string() });
const candidateSchema = z.object({ sourceID: z.enum(["launch", "support"]), sourceRevision: z.number().int().min(1).max(2), recipe: z.literal(RECIPE), fields: fieldsSchema, evidenceIDs: z.array(z.string()).min(1), unknowns: z.array(z.string()) });
export type Fields = z.infer<typeof fieldsSchema>;
export type Candidate = z.infer<typeof candidateSchema>;
const previousSchema = z.object({ fields: fieldsSchema, candidate: candidateSchema.nullable(), sourceRevision: z.number() });
const reviewSchema = z.object({
  id: z.string(), noteID: z.enum(["launch", "support"]), sourceRevision: z.number(),
  fields: fieldsSchema, candidate: candidateSchema.nullable(), staged: candidateSchema.nullable(), previous: previousSchema.nullable(),
  editVersion: z.number().int(), reviewed: z.boolean(),
  status: z.enum(["idle", "preparing", "ready", "interrupted", "failed", "waiting"]),
  requestID: z.string().nullable(), requestRevision: z.number().nullable(), error: z.string().nullable(),
});
export type Review = z.infer<typeof reviewSchema>;
const draftSchema = z.object({ id: z.string(), noteID: z.string(), sourceRevision: z.number(), fields: fieldsSchema, evidenceIDs: z.array(z.string()), unknowns: z.array(z.string()), editVersion: z.number(), savedAt: z.string() });
const stateSchema = z.object({ version: z.literal(1), revisions: z.record(z.string(), z.number().int().min(1).max(2)), reviews: z.record(z.string(), reviewSchema), drafts: z.record(z.string(), draftSchema) });
export type PrototypeState = z.infer<typeof stateSchema>;
export const emptyState = (): PrototypeState => ({version:1,revisions:{},reviews:{},drafts:{}});

function replace(state: PrototypeState, review: Review): PrototypeState {
  return {...state,reviews:{...state.reviews,[review.noteID]:review}};
}
export function beginPreparation(state: PrototypeState, note: SampleNote, requestID: string): PrototypeState {
  const review = state.reviews[note.id] ?? {
    id:`${note.id}:${RECIPE}`,noteID:note.id as Review["noteID"],sourceRevision:note.revision,
    fields:{recipient:"",subject:"",body:""},candidate:null,staged:null,previous:null,editVersion:0,reviewed:false,
    status:"idle" as const,requestID:null,requestRevision:null,error:null,
  };
  return replace(state,{...review,status:"preparing",requestID,requestRevision:note.revision,error:null});
}
export function validateCandidate(value: unknown, note: SampleNote): Candidate {
  const parsed = candidateSchema.safeParse(value);
  if(!parsed.success) throw new Error("The sample suggestion could not be read. Your edits are unchanged.");
  const candidate = parsed.data;
  if (candidate.sourceID !== note.id || candidate.sourceRevision !== note.revision || candidate.evidenceIDs.some(id => !note.evidence.some(span => span.id === id)))
    throw new Error("The sample suggestion could not be matched to this note. Your edits are unchanged.");
  if (candidate.fields.recipient) throw new Error("The sample source has no verified recipient. Your edits are unchanged.");
  return candidate;
}
export function completePreparation(state: PrototypeState, note: SampleNote, requestID: string, value: unknown): PrototypeState {
  const review = state.reviews[note.id];
  if (!review || review.requestID !== requestID || review.requestRevision !== note.revision) return state;
  const candidate = validateCandidate(value,note);
  if (!review.candidate && review.editVersion === 0) return replace(state,{...review,candidate,fields:candidate.fields,sourceRevision:note.revision,status:"ready",requestID:null,requestRevision:null,error:null});
  return replace(state,{...review,staged:candidate,status:"ready",requestID:null,requestRevision:null,error:null});
}
export function stopPreparation(state: PrototypeState, noteID: string): PrototypeState {
  const review=state.reviews[noteID];
  return !review || review.status!=="preparing" ? state : replace(state,{...review,status:"interrupted",requestID:null,requestRevision:null,error:"Sample preparation stopped. Your existing edits were kept."});
}
export function failPreparation(state: PrototypeState, noteID: string, requestID: string, message: string, waiting = false): PrototypeState {
  const review=state.reviews[noteID];
  return !review || review.requestID!==requestID ? state : replace(state,{...review,status:waiting?"waiting":"failed",error:message,requestID:null,requestRevision:null});
}
export function editDraft(state: PrototypeState, noteID: string, patch: Partial<Fields>): PrototypeState {
  const review=state.reviews[noteID];
  return replace(state,{...review,fields:{...review.fields,...patch},editVersion:review.editVersion+1,reviewed:false});
}
export function acceptSuggestion(state: PrototypeState, noteID: string): PrototypeState {
  const review=state.reviews[noteID], candidate=review.staged;
  if (!candidate || review.status==="preparing") return state;
  return replace(state,{...review,previous:{fields:review.fields,candidate:review.candidate,sourceRevision:review.sourceRevision},
    fields:{...candidate.fields,recipient:review.fields.recipient},candidate,sourceRevision:candidate.sourceRevision,
    staged:null,editVersion:review.editVersion+1,reviewed:false});
}
export function undoSuggestion(state: PrototypeState, noteID: string): PrototypeState {
  const review=state.reviews[noteID];
  return !review.previous ? state : replace(state,{...review,...review.previous,previous:null,editVersion:review.editVersion+1,reviewed:false});
}
export function keepDraft(state: PrototypeState, noteID: string): PrototypeState {
  return replace(state,{...state.reviews[noteID],staged:null});
}
export function setReviewed(state: PrototypeState, noteID: string, reviewed: boolean): PrototypeState {
  return replace(state,{...state.reviews[noteID],reviewed});
}
export function reviseSampleSource(state: PrototypeState, noteID: string, revision: number): PrototypeState {
  const interrupted=stopPreparation(state,noteID), review=interrupted.reviews[noteID];
  const next={...interrupted,revisions:{...interrupted.revisions,[noteID]:revision}};
  return review ? replace(next,{...review,reviewed:false}) : next;
}
export function unresolvedDetails(review: Review): string[] {
  return [...(review.candidate?.unknowns ?? []),...(!review.fields.recipient ? ["No recipient address was provided in the note."] : [])];
}
export function saveLocalDraft(state: PrototypeState, note: SampleNote, savedAt: string): PrototypeState {
  const review=state.reviews[note.id];
  if (!review?.candidate || review.status==="preparing" || review.sourceRevision!==note.revision || !review.reviewed)
    throw new Error("Review the current note and unresolved details before saving this draft.");
  if (!review.fields.subject.trim() || !review.fields.body.trim()) throw new Error("Add a subject and message before saving.");
  if (review.fields.recipient && !z.email().safeParse(review.fields.recipient).success) throw new Error("Use a valid recipient address or leave it unset for this local draft.");
  const id=review.id;
  const existing=state.drafts[id];
  if(existing?.editVersion===review.editVersion && existing.sourceRevision===review.sourceRevision) return state;
  return {...state,drafts:{...state.drafts,[id]:{id,noteID:note.id,sourceRevision:review.sourceRevision,fields:{...review.fields},evidenceIDs:[...review.candidate.evidenceIDs],unknowns:unresolvedDetails(review),editVersion:review.editVersion,savedAt}}};
}

export type StoragePort = Pick<Storage,"getItem"|"setItem">;
export class PrototypeStorage {
  private locked = false;
  private baseline: string|null|undefined;
  constructor(private storage: StoragePort) {}
  load(): PrototypeState {
    const raw=this.storage.getItem(STORAGE_KEY);
    this.baseline=raw;
    if(!raw) return emptyState();
    try {
      let state=stateSchema.parse(JSON.parse(raw));
      for(const review of Object.values(state.reviews)) state=stopPreparation(state,review.noteID);
      return state;
    } catch {
      this.locked=true;
      throw new Error("Saved prototype data could not be read. It has been left untouched; new edits will stay in this tab.");
    }
  }
  write(state: PrototypeState) {
    if(this.locked) throw new Error("The existing prototype data is unreadable and has been left untouched. New edits are only held in this tab.");
    const current=this.storage.getItem(STORAGE_KEY);
    if(this.baseline!==undefined && current!==this.baseline)
      throw new Error("This prototype changed in another tab. Your new edits are held here; copy them before reloading to review the other version.");
    const next=JSON.stringify(stateSchema.parse(state));
    this.storage.setItem(STORAGE_KEY,next);this.baseline=next;
  }
}

export interface FollowUpProvider {
  readonly id: string;
  readonly label: string;
  readonly funding: string;
  readonly capabilities: { text: boolean; transcription: boolean };
  prepare(note: SampleNote, signal: AbortSignal): Promise<Candidate>;
}
export class PrototypeProviderError extends Error {
  constructor(message: string, readonly kind: "quota"|"unavailable"|"unsupported") { super(message); }
}
export class MockFollowUpProvider implements FollowUpProvider {
  readonly id="synthetic-mock";
  readonly label="Fixed sample suggestion";
  readonly funding="No model usage or cost";
  readonly capabilities={text:true,transcription:false};
  constructor(private delay=900,private outcome: "normal"|"failure"|"quota"="normal") {}
  async prepare(note: SampleNote, signal: AbortSignal): Promise<Candidate> {
    await new Promise<void>((resolve,reject)=>{
      if(signal.aborted) { reject(new DOMException("Cancelled","AbortError")); return; }
      const stop=()=>{clearTimeout(timer);reject(new DOMException("Cancelled","AbortError"));};
      const timer=setTimeout(()=>{signal.removeEventListener("abort",stop);resolve();},this.delay);
      signal.addEventListener("abort",stop,{once:true});
    });
    if(this.outcome==="quota") throw new PrototypeProviderError("Simulated quota limit. Your draft is kept; retry the sample when ready.","quota");
    if(this.outcome==="failure") throw new PrototypeProviderError("The mock provider stopped. Your edits are kept; try the sample again.","unavailable");
    return {sourceID:note.id as Candidate["sourceID"],sourceRevision:note.revision,recipe:RECIPE,
      fields:{recipient:"",subject:note.subject,body:note.body},evidenceIDs:note.evidence.map(span=>span.id),unknowns:note.unknowns};
  }
}
/** Cancelled/superseded providers cannot return a candidate, even if they ignore abort. */
export class FollowUpRequest {
  private current?: AbortController;
  cancel() { this.current?.abort(); this.current=undefined; }
  async run(provider: FollowUpProvider, note: SampleNote) {
    this.cancel();const request=new AbortController();this.current=request;
    try {
      if(!provider.capabilities.text) throw new PrototypeProviderError("This provider cannot prepare text drafts. Existing edits are kept.","unsupported");
      const candidate=await provider.prepare(note,request.signal);
      if(this.current!==request || request.signal.aborted)return null;
      return {candidate:validateCandidate(candidate,note)};
    } catch(error) {
      if(this.current!==request || request.signal.aborted)return null;
      return {error:error instanceof Error?error.message:"Sample preparation failed. Your edits are unchanged.",waiting:error instanceof PrototypeProviderError && error.kind==="quota"};
    }
  }
}
