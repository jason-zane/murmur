import {beforeEach,describe,expect,it,vi} from "vitest";
const mocks=vi.hoisted(()=>({from:vi.fn(),connections:vi.fn(),own:vi.fn(),draft:vi.fn(),getDraft:vi.fn(),getUser:vi.fn(),rpc:vi.fn()}));
vi.mock("../src/lib/supabase/server",()=>({adminClient:()=>({from:mocks.from}),serverClient:async()=>({auth:{getUser:mocks.getUser},rpc:mocks.rpc,from:mocks.from}),bearerClient:()=>({auth:{getUser:mocks.getUser},rpc:mocks.rpc,from:mocks.from})}));
vi.mock("../src/lib/calendar",()=>({connectionsFor:mocks.connections}));
vi.mock("../src/lib/mail/gmail",()=>({ownMailbox:mocks.own,draftRevision:(payload:{revision:string})=>payload.revision}));
import {saveWorkspaceDraft,editableDraftSchema} from "../src/lib/mail/workspace-drafts";
import {POST} from "../src/app/api/mail/route";
import type {Compose} from "../src/lib/mail/model";
const account="00000000-0000-4000-8000-000000000001",other="00000000-0000-4000-8000-000000000002",id="10000000-0000-4000-8000-000000000001";
let rows:Map<string,any>,beforeWrite:(()=>void)|undefined;
function query(){let op="read",patch:any,filters:((r:any)=>boolean)[]=[];const q:any={select:()=>q,eq:(key:string,v:unknown)=>{filters.push(r=>r[key]===v);return q;},in:(key:string,v:unknown[])=>{filters.push(r=>v.includes(r[key]));return q;},update:(v:any)=>{op="update";patch=v;return q;},insert:(v:any)=>{op="insert";patch=v;return q;},maybeSingle:()=>run(),single:()=>run(),then:(resolve:any,reject:any)=>run().then(resolve,reject)};async function run(){if(op!=="read"&&beforeWrite){const f=beforeWrite;beforeWrite=undefined;f();}if(op==="insert"){if(rows.has(patch.id))return {data:null,error:{code:"23505"}};const r={gmail_state:"unsynced",gmail_error:null,...structuredClone(patch)};rows.set(r.id,r);return {data:structuredClone(r),error:null};}const row=[...rows.values()].find(r=>filters.every(f=>f(r)));if(!row)return {data:null,error:null};if(op==="update")Object.assign(row,structuredClone(patch));return {data:structuredClone(row),error:null};}return q;}
const message=(patch:Partial<Compose>={}):Compose=>({connection_id:account,to:["priya@example.com"],cc:[],bcc:[],subject:"A synthetic reply",text:"Confirm the owner first.",attachments:[],...patch});
const save=(m=message(),version=0,uuid=id)=>saveWorkspaceDraft("owner",{workspace_id:uuid,workspace_version:version,message:m});
beforeEach(()=>{vi.resetAllMocks();rows=new Map();beforeWrite=undefined;mocks.from.mockImplementation(query);mocks.connections.mockResolvedValue([{id:account,scopes:["https://www.googleapis.com/auth/gmail.modify"]},{id:other,scopes:["https://www.googleapis.com/auth/gmail.modify"]}]);mocks.own.mockResolvedValue({account:{email:"sam@example.com"},api:{draft:mocks.draft,getDraft:mocks.getDraft}});mocks.draft.mockResolvedValue({id:"provider-draft"});mocks.getDraft.mockResolvedValue({message:{payload:{revision:"revision-1"}}});mocks.getUser.mockResolvedValue({data:{user:{id:"owner"}},error:null});mocks.rpc.mockResolvedValue({data:true});});
describe("Concourse and Gmail draft saving",()=>{
 it("saves first-party content before requesting Gmail and replays a lost acknowledgement without a second provider copy",async()=>{
  mocks.draft.mockImplementation(async()=>{expect(rows.get(id).document.text).toBe("Confirm the owner first.");expect(rows.get(id).gmail_state).toBe("pending");return {id:"provider-draft"};});
  const first=await save();expect(first).toMatchObject({concourse_saved:true,gmail_saved:true,workspace_version:1,id:"provider-draft"});
  expect(await save()).toEqual(first);expect(mocks.draft).toHaveBeenCalledTimes(1);
 });
 it("retains incomplete recipients in Concourse without asking Gmail to create an invalid draft",async()=>{
  const result=await save(message({to:["priya@"]}));expect(result.concourse_saved).toBe(true);expect(result.gmail_saved).toBe(false);expect(rows.get(id).document.to).toEqual(["priya@"]);expect(mocks.own).not.toHaveBeenCalled();
 });
 it("retains edited content after provider access fails",async()=>{
  mocks.own.mockRejectedValueOnce(Error("Reconnect this inbox."));const result=await save();expect(result).toMatchObject({concourse_saved:true,gmail_saved:false,gmail_error:"Reconnect this inbox."});expect(rows.get(id).gmail_state).toBe("error");
 });
 it("preserves a Gmail conflict instead of overwriting it",async()=>{
  const result=await save(message({id:"external-draft",revision:"older"}));expect(result.gmail_error).toContain("changed in Gmail");expect(rows.get(id).document.text).toBe("Confirm the owner first.");expect(mocks.draft).not.toHaveBeenCalled();
 });
 it("does not repeat a provider creation whose acknowledgement was interrupted",async()=>{
  mocks.draft.mockRejectedValueOnce(Error("Timed out"));expect((await save()).gmail_saved).toBe(false);expect(rows.get(id).gmail_state).toBe("uncertain");
  await save(message({text:"Further edit kept in Concourse."}),1);expect(rows.get(id).document.text).toBe("Further edit kept in Concourse.");expect(mocks.draft).toHaveBeenCalledTimes(1);
 });
 it("rejects edits during an active provider save and protects second-session edits with an atomic version check",async()=>{
  await save();rows.get(id).gmail_state="pending";await expect(save(message({text:"New text"}),1)).rejects.toThrow("in progress");
  rows.get(id).gmail_state="synced";beforeWrite=()=>{rows.get(id).version=2;rows.get(id).document.text="Other session";};await expect(save(message({text:"My text"}),1)).rejects.toThrow("changed in another session");expect(rows.get(id).document.text).toBe("Other session");
 });
 it("does not acknowledge an old copy after another session changes it before the provider claim",async()=>{
  mocks.own.mockImplementationOnce(async()=>{rows.get(id).version=2;rows.get(id).document.text="Second session";return {account:{email:"sam@example.com"},api:{draft:mocks.draft,getDraft:mocks.getDraft}};});
  await expect(save()).rejects.toThrow("changed during saving");expect(rows.get(id).document.text).toBe("Second session");expect(mocks.draft).not.toHaveBeenCalled();
 });
 it("does not bind a workspace draft to a different sender or another owner's UUID",async()=>{
  await save();await expect(save(message({connection_id:other}),1)).rejects.toThrow("separate draft");rows.get(id).user_id="another-owner";await expect(save()).rejects.toThrow("changed in another session");expect(mocks.draft).toHaveBeenCalledTimes(1);
 });
 it("keeps an existing disconnected sender’s draft editable in Concourse without requesting Gmail",async()=>{
  await save();rows.get(id).connection_id=null;mocks.connections.mockResolvedValue([]);mocks.own.mockRejectedValueOnce(Error("Sender disconnected"));
  const result=await save(message({id:"provider-draft",revision:"revision-1",text:"Kept without Gmail"}),1);expect(result).toMatchObject({concourse_saved:true,gmail_saved:false});expect(rows.get(id).document.text).toBe("Kept without Gmail");expect(rows.get(id).connection_id).toBeNull();
 });
 it("supports updating a matching draft and recording the latest verified provider revision",async()=>{
  await save();const result=await save(message({id:"provider-draft",revision:"revision-1",text:"Updated wording"}),1);expect(result.workspace_version).toBe(2);expect(rows.get(id).document.text).toBe("Updated wording");expect(mocks.draft).toHaveBeenCalledTimes(2);
 });
 it("checks authentication and first-party editor access before cloud persistence",async()=>{
  const request=()=>new Request("http://localhost/api/mail",{method:"POST",headers:{authorization:"Bearer synthetic"},body:JSON.stringify({action:"workspace_draft",workspace_id:id,workspace_version:0,message:message()})});
  mocks.getUser.mockResolvedValueOnce({data:{user:null},error:Error("bad")});expect((await POST(request())).status).toBe(401);
  mocks.rpc.mockResolvedValueOnce({data:false});expect((await POST(request())).status).toBe(403);expect(mocks.from).not.toHaveBeenCalled();
  expect((await POST(request())).status).toBe(200);
 });
 it("bounds recoverable payloads and denies disconnected senders",async()=>{
  expect(editableDraftSchema.safeParse(message({to:Array(101).fill("incomplete")})).success).toBe(false);mocks.connections.mockResolvedValue([]);await expect(save()).rejects.toThrow("no longer connected");expect(rows.size).toBe(0);
 });
});
