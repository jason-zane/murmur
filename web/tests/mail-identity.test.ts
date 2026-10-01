import {afterEach,beforeEach,describe,expect,it,vi} from "vitest";
import {mailboxColour,mailboxIcon} from "../src/lib/mail/identity";
import {createWorkspacePreview} from "../src/lib/workspace-preview";
const transport=vi.hoisted(()=>({getUser:vi.fn(),rpc:vi.fn(),connections:vi.fn(),upsert:vi.fn(),from:vi.fn()}));
vi.mock("../src/lib/supabase/server",()=>({serverClient:async()=>({auth:{getUser:transport.getUser},rpc:transport.rpc}),bearerClient:()=>({auth:{getUser:transport.getUser},rpc:transport.rpc}),adminClient:()=>({from:transport.from})}));
vi.mock("../src/lib/calendar",()=>({connectionsFor:transport.connections}));
import {POST} from "../src/app/api/mail/route";
const account="00000000-0000-4000-8000-000000000001";
const request=(body:unknown,headers:Record<string,string>={authorization:"Bearer synthetic-owner"})=>new Request("http://localhost/api/mail",{method:"POST",headers,body:JSON.stringify(body)});
beforeEach(()=>{
 vi.resetAllMocks();transport.getUser.mockResolvedValue({data:{user:{id:"synthetic-owner"}},error:null});transport.rpc.mockResolvedValue({data:true,error:null});
 transport.connections.mockResolvedValue([{id:account,scopes:["https://www.googleapis.com/auth/gmail.modify"]}]);transport.from.mockReturnValue({upsert:transport.upsert});transport.upsert.mockResolvedValue({error:null});
});
afterEach(()=>vi.unstubAllEnvs());
describe("mailbox appearance",()=>{
 it("has stable UTF-8 defaults, explicit overrides and no-logo option",()=>{
  expect(mailboxColour({id:"account"})).toBe("slate");expect(mailboxColour({id:"sample-work"})).toBe("amber");expect(mailboxColour({id:"é"})).toBe("slate");expect(mailboxColour({id:"account",identity_colour:"teal"})).toBe("teal");expect(mailboxIcon({id:"account"})).toBe("initials");expect(mailboxIcon({id:"account",identity_icon:"none"})).toBe("none");
 });
 it("updates only supplied preference columns, without a Gmail request or signature reset",async()=>{
  const response=await POST(request({action:"preferences",account,identity_colour:"teal",identity_icon:"work"}));expect(response.status).toBe(200);expect(response.headers.get("cache-control")).toBe("private, no-store");
  expect(transport.connections).toHaveBeenCalledWith("synthetic-owner");expect(transport.from).toHaveBeenCalledWith("mail_preferences");expect(transport.upsert).toHaveBeenCalledExactlyOnceWith({connection_id:account,user_id:"synthetic-owner",identity_colour:"teal",identity_icon:"work"},{onConflict:"connection_id"});
 });
 it("retains old-client signature updates and allows explicit default resets",async()=>{
  expect((await POST(request({action:"preferences",account,signature:"Regards"}))).status).toBe(200);expect(transport.upsert.mock.calls[0][0]).not.toHaveProperty("identity_colour");
  expect((await POST(request({action:"preferences",account,identity_colour:null,identity_icon:null}))).status).toBe(200);expect(transport.upsert.mock.calls[1][0]).not.toHaveProperty("signature");
 });
 it.each([{identity_colour:"red"},{identity_icon:"https://logo.invalid"},{user_id:"other-owner"},{}])("rejects unknown values or authority fields %j before storage",async patch=>{
  expect((await POST(request({action:"preferences",account,...patch}))).status).toBe(400);expect(transport.upsert).not.toHaveBeenCalled();
 });
 it("denies another owner's or non-mail connection",async()=>{
  transport.connections.mockResolvedValueOnce([{id:account,scopes:[]}]);expect((await POST(request({action:"preferences",account,identity_colour:"teal"}))).status).toBe(404);
  transport.connections.mockResolvedValueOnce([]);expect((await POST(request({action:"preferences",account,identity_colour:"teal"}))).status).toBe(404);expect(transport.upsert).not.toHaveBeenCalled();
 });
 it("enforces real Auth/editor/CSRF logic around mocked transports",async()=>{
  transport.getUser.mockResolvedValueOnce({data:{user:null},error:Error("Forged token")});expect((await POST(request({action:"preferences",account,identity_colour:"teal"}))).status).toBe(401);
  transport.rpc.mockResolvedValueOnce({data:false});expect((await POST(request({action:"preferences",account,identity_colour:"teal"}))).status).toBe(403);
  expect((await POST(request({action:"preferences",account,identity_colour:"teal"},{origin:"https://unrelated.invalid"}))).status).toBe(403);expect(transport.upsert).not.toHaveBeenCalled();
 });
 it("persists isolated synthetic appearance across reload without changing the other mailbox",async()=>{
  const data=new Map<string,string>(),storage={getItem:(key:string)=>data.get(key) ?? null,setItem:(key:string,value:string)=>{data.set(key,value);}};
  const first=createWorkspacePreview(storage);await first.mail({}, {action:"preferences",account:"sample-work",identity_colour:"teal",identity_icon:"work",signature:"Sam"});
  const restarted=await createWorkspacePreview(storage).mail();expect(restarted.accounts[0].identity_colour).toBe("teal");expect(restarted.accounts[0].identity_icon).toBe("work");expect(restarted.accounts[1].identity_colour).toBeUndefined();
 });
 it("preserves unreadable preference storage and refuses a false save acknowledgement",async()=>{
  const existing="{broken",storage={getItem:(key:string)=>key.includes("mail-identity")?existing:null,setItem:vi.fn()};
  const preview=createWorkspacePreview(storage);
  await expect(preview.mail({}, {action:"preferences",account:"sample-work",identity_colour:"teal"})).rejects.toThrow("Original storage is preserved");expect(storage.setItem).not.toHaveBeenCalled();
 });
});
