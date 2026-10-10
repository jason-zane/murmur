import { describe,it,expect,vi } from "vitest";
import { createWorkspacePreview } from "../src/lib/workspace-preview";
import type { Compose } from "../src/lib/mail/model";
const store=()=>{const values=new Map<string,string>();return {getItem:(k:string)=>values.get(k)??null,setItem:(k:string,v:string)=>{values.set(k,v);},values};};
const draft:Compose={connection_id:"sample-work",to:["priya@example.com"],cc:[],bcc:[],subject:"Check-in",text:"Confirm the owner before suggesting a time.",attachments:[]};
describe("isolated workspace design preview",()=>{
 it("never contacts a provider, including sends, dispatch and unknown requests",async()=>{
  const network=vi.spyOn(globalThis,"fetch").mockRejectedValue(Error("Unexpected network call"));
  try{const p=createWorkspacePreview(store());await p.mail();await p.notes("/api/sessions");for(const action of ["send","dispatch","retry"])await expect(p.mail({}, {action,message:draft})).rejects.toThrow("Sending is unavailable");expect((await p.notes("https://example.com/private")).status).toBe(400);expect(network).not.toHaveBeenCalled();}finally{network.mockRestore();}
 });
 it("persists an edited sample reply and refuses stale writes after reopening",async()=>{
  const storage=store(),first=createWorkspacePreview(storage);const saved=await first.mail({}, {action:"draft",message:draft});const reopened=createWorkspacePreview(storage);const got=await reopened.mail({account:"sample-work",draft:saved.id});expect(got.message.text).toBe(draft.text);expect(got.message.to).toBe("priya@example.com");await reopened.mail({}, {action:"draft",message:{...draft,id:saved.id,revision:saved.revision,text:"Newer edit"}});await expect(reopened.mail({}, {action:"draft",message:{...draft,id:saved.id,revision:saved.revision,text:"Old edit"}})).rejects.toThrow("changed");
 });
 it("refuses to overwrite edits committed by another preview tab",async()=>{
  const storage=store(),a=createWorkspacePreview(storage),b=createWorkspacePreview(storage);await a.mail({}, {action:"draft",message:draft});await expect(b.mail({}, {action:"draft",message:{...draft,text:"Stale tab"}})).rejects.toThrow("another tab");expect(storage.getItem("concourse:workspace-preview:v1")).not.toContain("Stale tab");
 });
 it("keeps mailbox context and archive changes isolated",async()=>{
  const p=createWorkspacePreview(store());const work=await p.mail({account:"sample-work"}),personal=await p.mail({account:"sample-personal"});expect(work.threads.every((t:{account_id:string})=>t.account_id==="sample-work")).toBe(true);expect(personal.threads[0].subject).toBe("Saturday walk");await p.mail({}, {action:"archive",account:"sample-work",id:"pilot"});expect((await p.mail({account:"sample-work",q:"in:inbox"})).threads.some((t:{id:string})=>t.id==="pilot")).toBe(false);expect((await p.mail({account:"sample-work",q:"in:all -in:inbox -in:spam -in:trash"})).threads[0].id).toBe("pilot");
 });
 it("saves sample note edits locally with version conflict protection",async()=>{
  const storage=store(),p=createWorkspacePreview(storage);const note=(await (await p.notes("/api/sessions")).json()).sessions[0];const request={method:"POST",body:JSON.stringify({document:{...note.document,note:"Edited sample"},expectedVersion:note.version})};expect((await p.notes("/api/sessions",request)).status).toBe(200);expect((await p.notes("/api/sessions",request)).status).toBe(409);const reopened=createWorkspacePreview(storage);expect((await (await reopened.notes("/api/sessions/launch")).json()).document.note).toBe("Edited sample");
 });
 it("preserves unreadable saved data and reports storage failures",async()=>{
  const storage=store();storage.setItem("concourse:workspace-preview:v1","not-json");const p=createWorkspacePreview(storage);expect((await p.notes("/api/sessions")).status).toBe(409);await expect(p.mail({}, {action:"draft",message:draft})).rejects.toThrow("preserved");expect(storage.getItem("concourse:workspace-preview:v1")).toBe("not-json");await expect(createWorkspacePreview({getItem:()=>null,setItem:()=>{throw Error("Disk full");}}).mail({}, {action:"draft",message:draft})).rejects.toThrow("Disk full");
 });
});
