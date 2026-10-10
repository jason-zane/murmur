import { z } from "zod";
import { documentSchema, sessionID, type CloudSession } from "../documents";
import { FOLLOW_UP_RECIPE, followUpDocument, type FollowUpDocument, type SavedFollowUp } from "./drafts";

export type FollowUpSnapshot = { draft: SavedFollowUp | null; sourceVersion: number; sourceChanged: boolean };
export type ReviewState = {
  source: CloudSession; document: FollowUpDocument; baseVersion: number;
  cloud: SavedFollowUp | null; conflict: FollowUpSnapshot | null;
  ready: boolean; saving: boolean; loading: boolean; connected: boolean;
  denied: boolean; error: string; storageError: string; status: string;
  staged: string | null; previous: FollowUpDocument | null;
};
const sourceSchema = z.object({ id: sessionID, title: z.string().min(1).max(1000), started_at: z.iso.datetime({offset:true}), updated_at: z.iso.datetime({offset:true}), version: z.number().int().positive(), deleted_at: z.null(), document: documentSchema }).refine(source=>source.document.session.id===source.id,{message:"The source document belongs to another note."});
// Local typing may exceed the server's unresolved-detail limits; retain it until corrected.
const recoveryDocument = followUpDocument.safeExtend({unknowns:z.array(z.string().min(1).max(10000)).max(5001)});
const legacyRecoverySchema = z.object({ version: z.literal(1), document: recoveryDocument, baseVersion: z.number().int().nonnegative() }).strict();
const currentRecoverySchema = z.object({ version: z.literal(2), document: recoveryDocument, baseVersion: z.number().int().nonnegative(), savedDocument: followUpDocument.nullable() }).strict();
const recoverySchema = z.discriminatedUnion("version", [legacyRecoverySchema, currentRecoverySchema]);
const savedSchema = z.object({ session_id: z.string(), version: z.number().int().positive(), document: followUpDocument, updated_at: z.string() });
const snapshotSchema = z.object({ draft: savedSchema.nullable(), sourceVersion: z.number().int().positive(), sourceChanged: z.boolean() });
export const recoveryKey = (user: string, note: string, tab: string) => `concourse:follow-up-recovery:v1:${encodeURIComponent(user)}:${encodeURIComponent(note)}:${encodeURIComponent(tab)}`;
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
function errorMessage(error: unknown, fallback: string) {
  if(error instanceof z.ZodError)return "The saved draft or source response was incomplete. Your edits are retained; refresh to try again.";
  if(error instanceof SyntaxError)return "The saved copy could not be read. Your edits are retained; refresh or retry.";
  if(error instanceof TypeError)return "Concourse could not be reached. Your edits are retained; refresh or retry.";
  return error instanceof Error?error.message:fallback;
}
export function initialReviewState(source: CloudSession): ReviewState {
  return { source, document: { sourceVersion: source.version, recipe: FOLLOW_UP_RECIPE, fields: { recipient: "", subject: `Follow-up: ${source.title}`.slice(0,200), body: "" }, evidence: [], unknowns: [], reviewed: false }, baseVersion: 0, cloud: null, conflict: null, ready: false, saving: false, loading: false, connected: false, denied: false, error: "", storageError: "", status: "", staged: null, previous: null };
}
export function sourceExcerpts(source: CloudSession) {
  const evidence: FollowUpDocument["evidence"] = [];
  for (const paragraph of (source.document.note || "").split(/\n\s*\n/)) {
    const text=paragraph.trim();
    if(text && !/^#{1,6}\s+[^\n]+$/.test(text)) evidence.push({ kind: "note", id: "note", text: text.slice(0,2000) });
  }
  for(const line of source.document.transcript) evidence.push({ kind: "transcript", id: line.id, text: line.text.slice(0,2000) });
  for(const line of source.document.bullets) evidence.push({ kind: "bullet", id: line.id, text: line.text.slice(0,2000) });
  return evidence.filter((item,index,all)=>item.text.trim() && all.findIndex(other=>same(item,other))===index);
}
/** Per-tab recovery permits independent edits in two sessions without overwriting either. */
export class FollowUpRecovery {
  private loaded=false;
  private baseline: string | null=null;
  constructor(private storage: Pick<Storage,"getItem"|"setItem"> | undefined, private key: string) {}
  read() {
    if(!this.storage) throw Error("Browser recovery is unavailable. Keep this review open until saved.");
    this.baseline=this.storage.getItem(this.key);
    let result: z.infer<typeof recoverySchema> | null;
    try { result=this.baseline?recoverySchema.parse(JSON.parse(this.baseline)):null; }
    catch { throw Error("The recovery draft could not be read. Its original data is preserved."); }
    this.loaded=true;return result;
  }
  write(document: FollowUpDocument, baseVersion: number, savedDocument: FollowUpDocument | null = null) {
    if(!this.storage || !this.loaded) throw Error("Recovery storage is unavailable. Keep this review open until saved.");
    if(this.storage.getItem(this.key)!==this.baseline) throw Error("This recovery draft changed elsewhere. Keep this review open; no saved copy was replaced.");
    const value=JSON.stringify(currentRecoverySchema.parse({ version: 2, document, baseVersion, savedDocument }));
    if(value===this.baseline)return;
    try { this.storage.setItem(this.key,value); } catch { throw Error("This browser could not keep a recovery draft. Keep this review open until saved."); }
    this.baseline=value;
  }
}

/** Real HTTP adapter with explicit retries, cancellation and late-response exclusion. */
export class FollowUpReviewSession {
  state: ReviewState;
  private sequence=0;
  private abort: AbortController | null=null;
  private disposed=false;
  private recoveryLoaded=false;
  // A real baseline distinguishes unsaved wording from a clean saved copy after reload.
  // Legacy recovery lacks this information and is retained conservatively.
  private savedDocument: FollowUpDocument | null;
  constructor(source: CloudSession, private recovery: FollowUpRecovery, private request: typeof fetch, private publish: (state: ReviewState)=>void, private onSource: (source: CloudSession)=>void=()=>{}) { this.state=initialReviewState(source);this.savedDocument=this.state.document; }
  private update(patch: Partial<ReviewState>) { this.state={...this.state,...patch};if(!this.disposed)this.publish(this.state); }
  private persist() {
    try { this.recovery.write(this.state.document,this.state.baseVersion,this.savedDocument);this.update({storageError:""}); }
    catch(error) { this.update({storageError:error instanceof Error?error.message:"Recovery draft could not be kept."}); }
  }
  private path() { return `/api/sessions/${encodeURIComponent(this.state.source.id)}/follow-up`; }
  private async response(path: string, init: RequestInit, signal: AbortSignal) {
    const response=await this.request(path,{...init,signal}),body=await response.json();
    if(!response.ok) { const error=new Error(body.error || "The follow-up could not be saved.") as Error & {status:number};error.status=response.status;throw error; }
    return body;
  }
  async load() {
    if(this.state.saving || this.state.loading || this.disposed)return;
    const ticket=++this.sequence;this.abort?.abort();const controller=new AbortController();this.abort=controller;
    if(!this.recoveryLoaded) {
      try { const local=this.recovery.read();if(local){this.savedDocument=local.version===2?local.savedDocument:null;this.update({document:local.document,baseVersion:local.baseVersion,status:"Follow-up recovered in this tab."});} }
      catch(error) { this.update({storageError:error instanceof Error?error.message:"Recovery could not load."}); }
      this.recoveryLoaded=true;
    }
    this.update({loading:true,error:""});
    try {
      let snapshot=snapshotSchema.parse(await this.response(this.path(),{},controller.signal));
      let source=this.state.source;
      if(snapshot.sourceVersion!==source.version) {
        const raw=await this.response(`/api/sessions/${encodeURIComponent(source.id)}`,{},controller.signal);
        source=sourceSchema.parse(raw);
        if(source.id!==this.state.source.id)throw Error("The source response belongs to another note.");
        if(source.version!==snapshot.sourceVersion)snapshot=snapshotSchema.parse(await this.response(this.path(),{},controller.signal));
        if(source.version!==snapshot.sourceVersion)throw Error("The note changed while refreshing. Keep your edits and try again.");
      }
      if(ticket!==this.sequence || controller.signal.aborted)return;
      if(snapshot.draft && snapshot.draft.session_id!==source.id)throw Error("The saved follow-up belongs to another note.");
      const current=this.state, local=current.document, hasLocal=this.dirty;
      const equal=Boolean(snapshot.draft && same(snapshot.draft.document,local));
      const conflicted=hasLocal && !equal && (snapshot.draft?.version || 0)!==current.baseVersion;
      const chosen=!hasLocal?(snapshot.draft?.document || initialReviewState(source).document):local;
      const document=chosen.sourceVersion===source.version?chosen:{...chosen,reviewed:false};
      if(equal || !hasLocal)this.savedDocument=document;
      this.update({source,cloud:snapshot.draft,document,baseVersion:equal||!hasLocal?snapshot.draft?.version || 0:current.baseVersion,conflict:conflicted?snapshot:null,ready:true,connected:true,denied:false,status:conflicted?"A different saved copy is available. Compare both before choosing.":equal?"The saved copy matches this draft.":hasLocal?"Your local edits are retained.":snapshot.draft?"Saved follow-up opened.":"Choose evidence and write your follow-up."});
      this.onSource(source);this.persist();
    } catch(error) {
      if(ticket!==this.sequence || controller.signal.aborted)return;
      const denied=[401,403].includes((error as {status?:number}).status || 0);
      this.update({ready:true,connected:false,denied,document:{...this.state.document,reviewed:false},status:"The saved copy could not be checked. Your wording is retained.",error:errorMessage(error,"Saved draft could not open.")});this.persist();
    } finally {if(ticket===this.sequence)this.update({loading:false});}
  }
  edit(document: FollowUpDocument) {
    if(this.state.saving || this.state.loading || this.state.denied)return;
    this.update({document:{...document,reviewed:false},status:"Edits kept in this tab; save to keep them in Concourse.",error:""});this.persist();
  }
  setReviewed(value: boolean) {
    if(this.state.saving || this.state.loading || !this.state.connected || this.state.denied || this.state.conflict || this.state.document.sourceVersion!==this.state.source.version)return;
    const parsed=followUpDocument.safeParse({...this.state.document,reviewed:value});
    if(!parsed.success){this.update({error:"Confirm the recipient, wording, evidence and missing details first."});return;}
    this.update({document:parsed.data,error:""});this.persist();
  }
  private get canEdit() { return this.state.ready && !this.state.loading && !this.state.saving && !this.state.denied; }
  private replacementFits(body: string) {
    if(body.length<=10000)return true;
    this.update({staged:null,error:"Selected excerpts exceed the 10,000-character draft limit. Choose fewer excerpts; your wording is retained."});return false;
  }
  stageExcerpts() {
    if(!this.canEdit || this.state.document.sourceVersion!==this.state.source.version || !this.state.document.evidence.length)return;
    const staged=this.state.document.evidence.map(item=>item.text).join("\n\n");
    if(this.replacementFits(staged))this.update({staged,error:""});
  }
  acceptStaged() { if(!this.canEdit || this.state.staged===null || !this.replacementFits(this.state.staged))return;const previous=this.state.document;this.edit({...previous,fields:{...previous.fields,body:this.state.staged}});this.update({previous,staged:null}); }
  keepWording() { this.update({staged:null}); }
  useCurrentSource() { if(!this.canEdit)return;const previous=this.state.document;this.edit({...previous,sourceVersion:this.state.source.version,evidence:[]});this.update({previous,status:"Wording retained. Select evidence from the current note and review again."}); }
  resolveConflict(choice: "mine"|"cloud") {
    const conflict=this.state.conflict;if(!this.canEdit || !conflict)return;
    const previous=this.state.document,document=choice==="cloud"?(conflict.draft?.document || initialReviewState(this.state.source).document):previous;
    this.savedDocument=conflict.draft?.document || initialReviewState(this.state.source).document;
    this.update({document:{...document,reviewed:false},baseVersion:conflict.draft?.version || 0,cloud:conflict.draft,conflict:null,previous,status:choice==="mine"?"Your wording is kept. Review it before saving over the latest version.":"Showing the saved wording. Your earlier edits can be restored."});this.persist();
  }
  undo() {if(!this.canEdit || !this.state.previous)return;const previous=this.state.document;this.edit({...this.state.previous,reviewed:false});this.update({previous});}
  get dirty() { return this.savedDocument===null || !same(this.state.document,this.savedDocument); }
  async save() {
    if(this.state.saving || this.state.loading || !this.state.connected || this.state.denied || this.state.conflict || this.state.document.sourceVersion!==this.state.source.version || !this.dirty || this.disposed)return;
    const parsed=followUpDocument.safeParse(this.state.document);if(!parsed.success){this.update({error:"Check the draft fields before saving. Your edits are retained."});return;}
    const ticket=++this.sequence,document=parsed.data;this.abort?.abort();const controller=new AbortController();this.abort=controller;
    this.update({saving:true,error:"",status:"Saving follow-up…"});
    try {
      const body=await this.response(this.path(),{method:"PUT",headers:{"Content-Type":"application/json"},body:JSON.stringify({document,expectedVersion:this.state.baseVersion})},controller.signal);
      if(ticket!==this.sequence || controller.signal.aborted)return;
      const draft=savedSchema.parse(body.draft);
      if(draft.session_id!==this.state.source.id || !same(draft.document,document))throw Error("The save response does not match this draft. Reload to check its status.");
      this.savedDocument=draft.document;
      this.update({cloud:draft,baseVersion:draft.version,document:draft.document,status:draft.document.reviewed?"Reviewed draft saved in Concourse. No email sent.":"Unfinished draft saved in Concourse. No email sent."});this.persist();
    } catch(error) {
      if(ticket!==this.sequence || controller.signal.aborted)return;
      const denied=[401,403].includes((error as {status?:number}).status || 0);
      this.update({error:errorMessage(error,"Save failed. Your local edits are retained."),status:"Save not confirmed. Your edits are retained.",connected:!denied,denied,document:denied?{...this.state.document,reviewed:false}:this.state.document});if(denied)this.persist();
      if((error as {status?:number}).status===409) { this.update({saving:false});await this.load(); }
    } finally {if(ticket===this.sequence)this.update({saving:false});}
  }
  cancelSave() {if(!this.state.saving)return;this.sequence++;this.abort?.abort();this.update({saving:false,status:"Save interrupted. It may have reached Concourse; refresh or retry this same draft. Your edits are retained."});}
  dispose() {this.disposed=true;this.sequence++;this.abort?.abort();}
}
