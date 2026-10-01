import {beforeEach,describe,it,expect,vi} from "vitest";
import {HttpError} from "../src/lib/http";
const fixture=vi.hoisted(()=>({rows:[] as Record<string,any>[],call:vi.fn(),mailbox:vi.fn(),remove:vi.fn()}));
vi.mock("../src/lib/calendar",()=>({encryptToken:(v:string)=>`sealed:${v}`,decryptToken:(v:string)=>v.slice(7)}));
vi.mock("../src/lib/mail/gmail",()=>({ownMailbox:fixture.mailbox}));
vi.mock("../src/lib/supabase/server",()=>({adminClient:()=>({from:()=>{
 let mutation:Record<string,unknown>|undefined,single=false,cap=100;
 const filters:((r:Record<string,any>)=>boolean)[]=[];
 const query:any={
  select:()=>query,update:(v:Record<string,unknown>)=>{mutation=v;return query;},
  eq:(k:string,v:unknown)=>{filters.push(r=>r[k]===v);return query;},
  lt:(k:string,v:string)=>{filters.push(r=>r[k]<v);return query;},
  lte:(k:string,v:string)=>{filters.push(r=>r[k]<=v);return query;},
  order:()=>query,limit:(n:number)=>{cap=n;return query;},maybeSingle:()=>{single=true;return query;},
  then:(resolve:(v:unknown)=>unknown)=>{
   const matches=fixture.rows.filter(r=>filters.every(f=>f(r))).slice(0,cap);
   if(mutation) matches.forEach(r=>Object.assign(r,mutation));
   return Promise.resolve({data:single?(matches[0]?{...matches[0]}:null):matches.map(r=>({...r})),error:null}).then(resolve);
  },
 };return query;
}})}));
import {dispatchOutbox} from "../src/lib/mail/outbox";
const id="00000000-0000-4000-8000-000000000001";
function row(status="queued") {return {id,user_id:"owner",connection_id:"account",draft_id:"draft",status,due_at:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z",raw_message:"sealed:MIME"};}
beforeEach(()=>{
 vi.clearAllMocks();fixture.rows=[row()];
 fixture.mailbox.mockResolvedValue({api:{call:fixture.call,deleteDraft:fixture.remove}});
 fixture.call.mockResolvedValue({id:"sent-provider-id"});fixture.remove.mockResolvedValue({});
});
describe("durable Gmail delivery",()=>{
 it("claims once when workers race and removes the draft only after confirmation",async()=>{
  await Promise.all([dispatchOutbox("owner"),dispatchOutbox("owner")]);
  expect(fixture.call).toHaveBeenCalledTimes(1);expect(fixture.call).toHaveBeenCalledWith("messages/send","POST",{raw:"MIME"});
  expect(fixture.rows[0]).toMatchObject({status:"sent",provider_id:"sent-provider-id",raw_message:""});expect(fixture.remove).toHaveBeenCalledWith("draft");
 });
 it("never retries an acceptance timeout; reconciles Sent before clearing uncertainty",async()=>{
  fixture.call.mockRejectedValueOnce(new TypeError("connection interrupted"));await dispatchOutbox("owner");
  expect(fixture.rows[0].status).toBe("uncertain");expect(fixture.remove).not.toHaveBeenCalled();
  fixture.call.mockResolvedValueOnce({messages:[]});await dispatchOutbox("owner");expect(fixture.rows[0].status).toBe("uncertain");
  fixture.call.mockResolvedValueOnce({messages:[{id:"accepted"}]});await dispatchOutbox("owner");
  expect(fixture.rows[0]).toMatchObject({status:"sent",provider_id:"accepted",raw_message:""});
  expect(fixture.call.mock.calls.filter(c=>c[0]==="messages/send")).toHaveLength(1);
 });
 it("recovers a crashed sending worker without dispatching again",async()=>{
  fixture.rows=[row("sending")];fixture.call.mockResolvedValue({messages:[]});await dispatchOutbox("owner");
  expect(fixture.rows[0].status).toBe("uncertain");expect(fixture.call.mock.calls.every(c=>c[0]!=="messages/send")).toBe(true);
 });
 it("honours cancellation before claim and account ownership",async()=>{
  fixture.mailbox.mockImplementation(async()=>{fixture.rows[0].status="cancelled";return {api:{call:fixture.call}};});
  await dispatchOutbox("another-owner");expect(fixture.mailbox).not.toHaveBeenCalled();
  await dispatchOutbox("owner");expect(fixture.call).not.toHaveBeenCalled();
 });
 it("keeps drafts on a definite provider rejection",async()=>{
  fixture.call.mockRejectedValue(new HttpError(403,"Reconnect Gmail"));await dispatchOutbox("owner");
  expect(fixture.rows[0].status).toBe("failed");expect(fixture.remove).not.toHaveBeenCalled();
 });
});
