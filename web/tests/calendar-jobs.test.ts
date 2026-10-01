import {beforeEach,describe,it,expect,vi} from "vitest";
const fixture=vi.hoisted(()=>({jobs:[] as Record<string,any>[],page:vi.fn(),commit:vi.fn()}));
vi.mock("../src/lib/calendar",()=>({connectionsFor:async()=>[{id:"account",email:"owner@example.invalid",scopes:[]}],accessToken:async()=>"synthetic-token",syncSources:vi.fn()}));
vi.mock("../src/lib/google",async original=>({...await original<typeof import("../src/lib/google")>(),google:()=>({eventsPage:fixture.page})}));
vi.mock("../src/lib/supabase/server",()=>({adminClient:()=>({rpc:fixture.commit,from:(table:string)=>{
 let update:Record<string,unknown>|undefined,single=false,cap=100;
 const filters:((r:Record<string,any>)=>boolean)[]=[];
 const query:any={select:()=>query,update:(v:Record<string,unknown>)=>{update=v;return query;},
  eq:(k:string,v:unknown)=>{filters.push(r=>r[k]===v);return query;},in:(k:string,v:unknown[])=>{filters.push(r=>v.includes(r[k]));return query;},
  lt:(k:string,v:string)=>{filters.push(r=>r[k]<v);return query;},lte:(k:string,v:string)=>{filters.push(r=>r[k]<=v);return query;},
  order:()=>query,limit:(n:number)=>{cap=n;return query;},single:()=>{single=true;return query;},maybeSingle:()=>{single=true;return query;},
  then:(resolve:(v:unknown)=>unknown)=>{
   const rows=(table==="calendar_sources"?[{connection_id:"account",calendar_id:"primary",time_zone:"Australia/Sydney"}]:fixture.jobs).filter(r=>filters.every(f=>f(r))).slice(0,cap);
   if(update) rows.forEach(r=>Object.assign(r,update));return Promise.resolve({data:single?(rows[0]?{...rows[0]}:null):rows.map(r=>({...r})),error:null}).then(resolve);
  }};return query;
}})}));
import {runCalendarJobs,rangeJobKey} from "../src/lib/calendar-jobs";
import {GoogleError} from "../src/lib/google";
const event=(id:string)=>({id,start:{dateTime:"2026-10-01T00:00:00Z"},end:{dateTime:"2026-10-01T01:00:00Z"}});
beforeEach(()=>{
 vi.clearAllMocks();fixture.jobs=[{id:"job",user_id:"owner",connection_id:"account",calendar_id:"primary",kind:"range",starts_at:"2026-10-01T00:00:00Z",ends_at:"2026-10-08T00:00:00Z",status:"queued",retry_after:"2020-01-01T00:00:00Z",updated_at:"2020-01-01T00:00:00Z",attempts:0,dirty:false,staged:{},page_token:null}];
 fixture.commit.mockImplementation(async(_name:string,params:any)=>{const job=fixture.jobs[0];expect(params.p_lease).toBe(job.lease);job.status="complete";job.staged={};return {data:true,error:null};});
});
describe("resumable calendar ranges",()=>{
 it("checkpoints a page without replacing coverage when the next page fails",async()=>{
  fixture.page.mockResolvedValueOnce({items:[event("first")],nextPageToken:"next"}).mockRejectedValueOnce(new Error("provider offline"));
  await runCalendarJobs("owner");expect(fixture.commit).not.toHaveBeenCalled();expect(fixture.jobs[0]).toMatchObject({status:"failed",page_token:"next"});expect(fixture.jobs[0].staged.first.id).toBe("first");
  fixture.jobs[0].retry_after="2020-01-01T00:00:00Z";fixture.page.mockResolvedValueOnce({items:[event("second")]});await runCalendarJobs("owner");
  expect(fixture.page.mock.calls[2][3]).toBe("next");expect(fixture.commit.mock.calls[0][1].p_events.map((e:any)=>e.id)).toEqual(["first","second"]);expect(fixture.jobs[0].status).toBe("complete");
 });
 it("restarts an expired provider page token without committing a partial snapshot",async()=>{
  fixture.jobs[0].page_token="expired";fixture.jobs[0].staged={old:event("old")};fixture.page.mockRejectedValueOnce(new GoogleError(410,"cursor expired"));await runCalendarJobs("owner");
  expect(fixture.jobs[0]).toMatchObject({status:"failed",page_token:null,staged:{}});expect(fixture.commit).not.toHaveBeenCalled();
 });
 it("does not process another owner's queued job",async()=>{await runCalendarJobs("different-owner");expect(fixture.page).not.toHaveBeenCalled();expect(fixture.jobs[0].status).toBe("queued");});
 it("uses one job identity for equivalent date offsets",()=>{expect(rangeJobKey("account","primary","2026-10-01T10:00:00+10:00","2026-10-01T11:00:00+10:00")).toBe(rangeJobKey("account","primary","2026-10-01T00:00:00Z","2026-10-01T01:00:00Z"));});
});
