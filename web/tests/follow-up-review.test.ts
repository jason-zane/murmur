import { afterEach, describe, expect, it, vi } from "vitest";
import { createWorkspacePreview } from "../src/lib/workspace-preview";
import { FollowUpRecovery, FollowUpReviewSession, recoveryKey, sourceExcerpts } from "../src/lib/follow-up/review";
import type { CloudSession } from "../src/lib/documents";
function storage() {const values=new Map<string,string>();return {values,getItem:(key:string)=>values.get(key) ?? null,setItem:(key:string,value:string)=>{values.set(key,value);}};}
async function harness() {
  const cloud=storage(),transport=createWorkspacePreview(cloud).notes;
  const source:CloudSession=await (await transport("/api/sessions/launch")).json();
  const local=storage();
  const make=(tab:string,request=transport)=>new FollowUpReviewSession(source,new FollowUpRecovery(local,recoveryKey("owner",source.id,tab)),request,vi.fn());
  return {cloud,local,source,transport,make};
}
function wording(session:FollowUpReviewSession,body="My reviewed wording") {session.edit({...session.state.document,fields:{recipient:"sam@example.invalid",subject:"Pilot follow-up",body},evidence:[sourceExcerpts(session.state.source)[0]],unknowns:[]});}
afterEach(()=>vi.unstubAllGlobals());
describe("real follow-up review controller on isolated transport",()=>{
  it("persists unfinished edits and recovers them after close/reload",async()=>{
    const h=await harness(),first=h.make("first");await first.load();wording(first,"Unfinished wording");first.edit({...first.state.document,fields:{...first.state.document.fields,recipient:"sam@"},unknowns:["Owner still missing."]});first.dispose();
    const reopened=h.make("first");await reopened.load();expect(reopened.state.document.fields).toMatchObject({recipient:"sam@",body:"Unfinished wording"});expect(reopened.state.document.unknowns).toEqual(["Owner still missing."]);await reopened.save();expect(reopened.state.baseVersion).toBe(1);expect(reopened.state.document.reviewed).toBe(false);
  });
  it("recovers over-limit unresolved-detail typing while blocking invalid server saves",async()=>{
    const h=await harness(),request=vi.fn(h.transport),first=h.make("a",request);await first.load();wording(first);const unknowns=[...Array.from({length:21},(_,i)=>`Detail ${i}`),"x".repeat(501)];first.edit({...first.state.document,unknowns});expect(first.state.storageError).toBe("");first.dispose();
    const reopened=h.make("a",request);await reopened.load();expect(reopened.state.document.unknowns).toEqual(unknowns);await reopened.save();expect(reopened.state.error).toMatch(/Check the draft fields/);expect(request.mock.calls.some(([,init])=>init?.method==="PUT")).toBe(false);reopened.edit({...reopened.state.document,unknowns:["Confirm owner"]});await reopened.save();expect(reopened.state.baseVersion).toBe(1);
  });
  it("preserves another recovery writer if a cloned tab inherited the same identity",async()=>{
    const h=await harness(),a=h.make("cloned"),b=h.make("cloned");await a.load();await b.load();wording(a,"First tab recovery");wording(b,"Second tab working copy");expect(b.state.storageError).toMatch(/changed elsewhere/);expect(b.state.document.fields.body).toBe("Second tab working copy");expect(JSON.parse(h.local.getItem(recoveryKey("owner","launch","cloned"))!).document.fields.body).toBe("First tab recovery");
  });
  it("guards repeated clicks and deduplicates lost-response retries",async()=>{
    const h=await harness();let lost=true;
    const request=vi.fn<typeof fetch>(async(input,init)=>{const result=await h.transport(input,init);if(init?.method==="PUT"&&lost){lost=false;throw Error("Response lost after save.");}return result;});
    const session=h.make("one",request);await session.load();wording(session);session.setReviewed(true);
    await Promise.all([session.save(),session.save()]);expect(request.mock.calls.filter(([,init])=>init?.method==="PUT")).toHaveLength(1);expect(session.state.error).toMatch(/Response lost/);expect(session.state.status).toMatch(/Save not confirmed/);expect(session.state.saving).toBe(false);
    await session.save();expect(session.state.baseVersion).toBe(1);expect(session.state.document.reviewed).toBe(true);await session.save();expect(request.mock.calls.filter(([,init])=>init?.method==="PUT")).toHaveLength(2);
  });
  it("ignores late completion after cancel, retaining newer edits and reconciling the unknown save",async()=>{
    const h=await harness();let release=()=>{};
    const held=new Promise<void>(resolve=>{release=resolve;});
    const request:typeof fetch=async(input,init)=>{if(init?.method==="PUT")await held;return h.transport(input,init);};
    const session=h.make("one",request);await session.load();wording(session,"Before cancellation");const pending=session.save();session.cancelSave();wording(session,"After cancellation");release();await pending;
    expect(session.state.document.fields.body).toBe("After cancellation");expect(session.state.baseVersion).toBe(0);
    await session.load();expect(session.state.conflict?.draft?.document.fields.body).toBe("Before cancellation");session.resolveConflict("mine");await session.save();expect(session.state.baseVersion).toBe(2);expect(session.state.document.fields.body).toBe("After cancellation");
  });
  it("isolates recovery in two sessions and requires an explicit conflict decision",async()=>{
    const h=await harness(),a=h.make("a"),b=h.make("b");await a.load();wording(a,"Initial");await a.save();await b.load();
    wording(a,"Device A wording");wording(b,"Device B wording");await a.save();await b.save();
    expect(b.state.conflict?.draft?.document.fields.body).toBe("Device A wording");expect(b.state.document.fields.body).toBe("Device B wording");const version=b.state.baseVersion;await b.save();expect(b.state.baseVersion).toBe(version);
    b.resolveConflict("cloud");expect(b.state.document.fields.body).toBe("Device A wording");b.undo();expect(b.state.document.fields.body).toBe("Device B wording");expect(b.state.document.reviewed).toBe(false);await b.save();expect(b.state.baseVersion).toBe(3);
    expect(JSON.parse(h.local.getItem(recoveryKey("owner","launch","a"))!).document.fields.body).toBe("Device A wording");
  });
  it("invalidates old-source review without destroying edits and requires current evidence",async()=>{
    const h=await harness(),session=h.make("a");await session.load();wording(session);session.setReviewed(true);await session.save();
    const document={...h.source.document,note:"## Decision\n\nPause the pilot until the review is complete."};
    expect((await h.transport("/api/sessions",{method:"POST",body:JSON.stringify({document,expectedVersion:1})})).ok).toBe(true);
    await session.load();expect(session.state.source.version).toBe(2);expect(session.state.document.sourceVersion).toBe(1);expect(session.state.document.reviewed).toBe(false);expect(session.state.document.fields.body).toBe("My reviewed wording");await session.save();expect(session.state.baseVersion).toBe(1);
    session.useCurrentSource();expect(session.state.document.evidence).toEqual([]);session.setReviewed(true);expect(session.state.document.reviewed).toBe(false);
    session.edit({...session.state.document,evidence:[sourceExcerpts(session.state.source)[0]]});session.setReviewed(true);await session.save();expect(session.state.baseVersion).toBe(2);expect(session.state.document.sourceVersion).toBe(2);
  });
  it("stages excerpt replacement, keeps existing wording and restores earlier edits",async()=>{
    const h=await harness(),session=h.make("a");await session.load();wording(session,"My own message");session.stageExcerpts();expect(session.state.document.fields.body).toBe("My own message");session.keepWording();expect(session.state.staged).toBeNull();session.stageExcerpts();session.acceptStaged();expect(session.state.document.fields.body).toBe(sourceExcerpts(h.source)[0].text);session.undo();expect(session.state.document.fields.body).toBe("My own message");
  });
  it("blocks oversized excerpt replacements before touching wording or recovery",async()=>{
    const h=await harness(),session=h.make("size");await session.load();wording(session,"Keep my original message");
    const evidence=Array.from({length:6},(_,i)=>({kind:"note" as const,id:"note",text:String.fromCharCode(65+i).repeat(2000)}));
    session.edit({...session.state.document,evidence});session.stageExcerpts();
    expect(session.state.staged).toBeNull();expect(session.state.error).toMatch(/10,000/);session.acceptStaged();
    expect(session.state.document.fields.body).toBe("Keep my original message");expect(session.state.storageError).toBe("");session.dispose();
    const reopened=h.make("size");await reopened.load();expect(reopened.state.document.fields.body).toBe("Keep my original message");expect(reopened.state.document.evidence).toEqual(evidence);
  });
  it("accepts exactly 10,000 excerpt characters and retains undo/reload recovery",async()=>{
    const h=await harness(),session=h.make("size");await session.load();wording(session,"Earlier message");
    const evidence=Array.from({length:5},(_,i)=>({kind:"note" as const,id:"note",text:String.fromCharCode(65+i).repeat(i===4?1992:2000)}));
    session.edit({...session.state.document,evidence});session.stageExcerpts();expect(session.state.staged).toHaveLength(10000);session.acceptStaged();
    expect(session.state.document.fields.body).toHaveLength(10000);expect(session.state.storageError).toBe("");session.undo();expect(session.state.document.fields.body).toBe("Earlier message");
    session.dispose();const reopened=h.make("size");await reopened.load();expect(reopened.state.document.fields.body).toBe("Earlier message");
  });
  it.each([false,true])("clean refresh/reload adopts a newer saved version (reload=%s)",async reload=>{
    const h=await harness(),a=h.make("a");let b=h.make("b");await a.load();wording(a,"Initial saved message");await a.save();await b.load();
    expect(b.dirty).toBe(false);wording(a,"Latest saved message");await a.save();
    if(reload){b.dispose();b=h.make("b");}await b.load();
    expect(b.state.document.fields.body).toBe("Latest saved message");expect(b.state.baseVersion).toBe(2);expect(b.state.conflict).toBeNull();expect(b.dirty).toBe(false);
  });
  it("uses document changes rather than edit status to decide whether refresh conflicts",async()=>{
    const h=await harness(),a=h.make("a"),b=h.make("b");await a.load();wording(a,"Initial saved message");await a.save();await b.load();const baseline=b.state.document;
    wording(b,"Temporary edits");b.edit(baseline);expect(b.state.status).toMatch(/Edits kept/);expect(b.dirty).toBe(false);
    wording(a,"Latest saved message");await a.save();await b.load();expect(b.state.document.fields.body).toBe("Latest saved message");expect(b.state.conflict).toBeNull();
  });
  it.each([false,true])("dirty refresh/reload preserves edits and reports the new version (reload=%s)",async reload=>{
    const h=await harness(),a=h.make("a");let b=h.make("b");await a.load();wording(a,"Initial saved message");await a.save();await b.load();
    wording(b,"Unsaved local message");wording(a,"Latest saved message");await a.save();if(reload){b.dispose();b=h.make("b");}await b.load();
    expect(b.state.document.fields.body).toBe("Unsaved local message");expect(b.state.baseVersion).toBe(1);expect(b.state.conflict?.draft?.version).toBe(2);expect(b.dirty).toBe(true);
  });
  it("conservatively recovers legacy drafts with unknown clean/dirty baseline",async()=>{
    const h=await harness(),a=h.make("a");await a.load();wording(a,"Initial saved message");await a.save();
    h.local.setItem(recoveryKey("owner","launch","legacy"),JSON.stringify({version:1,baseVersion:1,document:a.state.document}));
    wording(a,"Latest saved message");await a.save();const legacy=h.make("legacy");await legacy.load();expect(legacy.state.document.fields.body).toBe("Initial saved message");expect(legacy.state.conflict?.draft?.version).toBe(2);
  });
  it.each([401,403])("denies edits/saves for HTTP %s while retaining local recovery",async status=>{
    const h=await harness(),initial=h.make("a");await initial.load();wording(initial,"Retain this draft");initial.setReviewed(true);initial.dispose();
    const request=vi.fn<typeof fetch>(async()=>Response.json({error:"Access unavailable"},{status})),blocked=h.make("a",request);await blocked.load();wording(blocked,"Forbidden edit");await blocked.save();expect(blocked.state.document.fields.body).toBe("Retain this draft");expect(blocked.state.denied).toBe(true);expect(blocked.state.document.reviewed).toBe(false);expect(request).toHaveBeenCalledTimes(1);
  });
  it("preserves corrupt/quota-failed recovery and reports the durability limit",async()=>{
    const h=await harness(),key=recoveryKey("owner","launch","bad");h.local.setItem(key,"corrupt");const session=h.make("bad");await session.load();wording(session);expect(h.local.getItem(key)).toBe("corrupt");expect(session.state.storageError).toMatch(/unavailable/);
    const recovery=new FollowUpRecovery({getItem:()=>null,setItem:()=>{throw Error("quota");}},"qa");recovery.read();expect(()=>recovery.write(session.state.document,0)).toThrow(/could not keep/);
  });
  it("cannot publish a late load after disposing the review",async()=>{
    const h=await harness();let release=()=>{};const hold=new Promise<void>(resolve=>{release=resolve;});const changed=vi.fn();
    const session=new FollowUpReviewSession(h.source,new FollowUpRecovery(h.local,"qa"),async(input,init)=>{await hold;return h.transport(input,init);},changed);const pending=session.load();session.dispose();changed.mockClear();release();await pending;expect(changed).not.toHaveBeenCalled();
  });
  it("never silently adopts a source that changed between the two snapshot reads",async()=>{
    const h=await harness();const request:typeof fetch=async(input)=>String(input).endsWith("/follow-up")?Response.json({draft:null,sourceVersion:2,sourceChanged:false}):Response.json({...h.source,version:3});
    const session=h.make("a",request);await session.load();expect(session.state.connected).toBe(false);expect(session.state.error).toMatch(/changed while refreshing/);expect(session.state.document.sourceVersion).toBe(1);
  });
  it("keeps offline edits recoverable but cannot approve without a current server snapshot",async()=>{
    const h=await harness();const session=h.make("offline",async()=>{throw Error("Offline");});await session.load();wording(session,"Offline wording");session.setReviewed(true);expect(session.state.document.reviewed).toBe(false);expect(session.state.document.fields.body).toBe("Offline wording");await session.save();expect(session.state.baseVersion).toBe(0);
    const reopened=h.make("offline");await reopened.load();expect(reopened.state.document.fields.body).toBe("Offline wording");reopened.setReviewed(true);expect(reopened.state.document.reviewed).toBe(true);
  });
  it("refuses malformed refreshed source metadata while preserving recovery",async()=>{
    const h=await harness(),first=h.make("a");await first.load();wording(first,"Keep my local wording");first.dispose();
    const request:typeof fetch=async(input)=>String(input).endsWith("/follow-up")?Response.json({draft:null,sourceVersion:2,sourceChanged:false}):Response.json({...h.source,version:"2"});
    const session=h.make("a",request);await session.load();expect(session.state.connected).toBe(false);expect(session.state.document.fields.body).toBe("Keep my local wording");expect(session.state.source.version).toBe(1);expect(session.state.error).toMatch(/response was incomplete/);
  });
  it("rejects incorrect response/source identity and never falls back to live fetch",async()=>{
    vi.stubGlobal("fetch",vi.fn(()=>{throw Error("Live fetch forbidden");}));const h=await harness(),session=h.make("a");await session.load();wording(session);await session.save();expect(fetch).not.toHaveBeenCalled();
    const wrong=h.make("b",async()=>Response.json({draft:{session_id:"other",version:1,updated_at:"now",document:session.state.document},sourceVersion:1,sourceChanged:false}));await wrong.load();expect(wrong.state.error).toMatch(/another note/);expect(wrong.state.connected).toBe(false);
  });
});
