import { describe,it,expect,vi } from "vitest";
import { InviteProposalStorage,acceptAvailability,availabilitySignature,editProposal,inviteInstant,newProposal,proposalKey,proposalProblems,reviewProposal,type InviteSource } from "../src/lib/invite-proposal";
import { sampleInviteCalendars,sampleInviteCheck } from "../src/lib/invite-preview";
const source:InviteSource={accountID:"sample-work",mailbox:"sam@example.com",messageID:"pilot",subject:"Pilot review",from:"priya@example.com",sentAt:"2026-09-30T09:42:00Z",text:"Can we meet Friday at 10? No time zone was agreed.",evidence:"Can we meet Friday at 10?"};
const complete=()=>editProposal(newProposal(source),{calendarID:"work",start:"2026-10-02T11:00",end:"2026-10-02T11:30",zone:"Australia/Sydney",guests:"priya@example.com"});
function memory(){const data=new Map<string,string>();return {getItem:(key:string)=>data.get(key) ?? null,setItem:(key:string,value:string)=>{data.set(key,value);},data};}
describe("email invitation proposals",()=>{
  it("retains tentative evidence without inventing dates, zones, durations or attendees",()=>{
    const p=newProposal(source);expect(p.fields).toMatchObject({start:"",end:"",zone:"",guests:"",calendarID:""});
    expect(proposalProblems(p,sampleInviteCalendars)).toHaveLength(5);
    expect(()=>newProposal({...source,evidence:"An invented confirmation"})).toThrow("quote");
  });
  it("requires a calendar in the chosen account, valid guests and increasing times",()=>{
    expect(proposalProblems(complete(),sampleInviteCalendars)).toEqual([]);
    expect(proposalProblems(editProposal(complete(),{accountID:"sample-personal"}),sampleInviteCalendars)[0]).toContain("destination");
    expect(proposalProblems(editProposal(complete(),{end:"2026-10-02T10:30",guests:"Priya"}),sampleInviteCalendars)).toEqual(expect.arrayContaining([expect.stringContaining("end after"),expect.stringContaining("valid attendee")]));
    expect(proposalProblems(editProposal(complete(),{guests:"priya@example.com, PRIYA@example.com"}),sampleInviteCalendars)).toContain("Remove duplicate attendee addresses.");
  });
  it("rejects skipped/repeated local hours and invalid zones instead of guessing an instant",()=>{
    expect(()=>inviteInstant("2026-10-04T02:30","Australia/Sydney")).toThrow("does not exist");
    expect(()=>inviteInstant("2026-11-01T01:30","America/New_York")).toThrow("occurs twice");
    expect(()=>inviteInstant("2026-04-05T01:45","Australia/Lord_Howe")).toThrow("occurs twice");
    expect(proposalProblems(editProposal(complete(),{zone:"Mars/Base"}),sampleInviteCalendars)).toContain("Choose a valid IANA time zone, such as Australia/Sydney.");
  });
  it("ignores stale availability and resets approval whenever details change",()=>{
    let p=complete();const signature=availabilitySignature(p.fields);
    p=acceptAvailability(p,signature,{status:"clear",detail:"Sample clear"},1000);p=reviewProposal(p,sampleInviteCalendars,1000);
    const next=editProposal(p,{start:"2026-10-02T12:00",end:"2026-10-02T12:30"});expect(next.reviewed).toBe(false);expect(next.availability).toBeNull();
    expect(acceptAvailability(next,signature,{status:"clear",detail:"Old response"},2000)).toBe(next);
    expect(editProposal(p,{title:"Edited title"}).availability?.status).toBe("clear");
  });
  it("cannot review missing, conflicting, unavailable or expired availability",()=>{
    const p=complete(),signature=availabilitySignature(p.fields);
    expect(()=>reviewProposal(p,sampleInviteCalendars,1000)).toThrow("Check sample");
    for(const status of ["conflict","unavailable"] as const)expect(()=>reviewProposal(acceptAvailability(p,signature,{status,detail:"Fixture"},1000),sampleInviteCalendars,1000)).toThrow();
    const checked=acceptAvailability(p,signature,{status:"clear",detail:"Fixture"},1000);
    expect(()=>reviewProposal(checked,sampleInviteCalendars,601001)).toThrow("again");
    const reviewed=reviewProposal(checked,sampleInviteCalendars,1001);expect(reviewProposal(reviewed,sampleInviteCalendars,1002)).toBe(reviewed);
  });
  it("restores incomplete edits through close/reload and saves the same proposal once",()=>{
    const storage=memory(),key=proposalKey("user",source),a=new InviteProposalStorage(storage,key);a.load(source);
    const p=editProposal(newProposal(source),{title:"Kept edits"});a.write(p);a.write(p);
    expect(storage.data.size).toBe(1);expect(new InviteProposalStorage(storage,key).load(source).proposal.fields.title).toBe("Kept edits");
    expect(proposalKey("other-user",source)).not.toBe(key);expect(proposalKey("user",{...source,accountID:"other-mailbox"})).not.toBe(key);
  });
  it("retains edits when the source changes while resetting review and availability",()=>{
    const storage=memory(),key=proposalKey("user",source),a=new InviteProposalStorage(storage,key);a.load(source);
    const checked=acceptAvailability(complete(),availabilitySignature(complete().fields),{status:"clear",detail:"Fixture"},1000);a.write(reviewProposal(checked,sampleInviteCalendars,1000));
    const changed={...source,text:source.text+" Now on Monday."},restored=new InviteProposalStorage(storage,key).load(changed);
    expect(restored.sourceChanged).toBe(true);expect(restored.proposal.fields).toEqual(checked.fields);expect(restored.proposal.reviewed).toBe(false);expect(restored.proposal.availability).toBeNull();
  });
  it("refuses cross-tab overwrites and preserves corrupt/unavailable data",()=>{
    const storage=memory(),key=proposalKey("user",source),a=new InviteProposalStorage(storage,key),b=new InviteProposalStorage(storage,key);a.load(source);b.load(source);a.write(complete());
    expect(()=>b.write(newProposal(source))).toThrow("another tab");
    const before=storage.getItem(key);storage.setItem(key,"bad-json");const broken=new InviteProposalStorage(storage,key);expect(()=>broken.load(source)).toThrow();expect(()=>broken.write(complete())).toThrow("preserved");expect(storage.getItem(key)).toBe("bad-json");
    expect(before).toContain("priya@example.com");expect(()=>new InviteProposalStorage(undefined,key).load(source)).toThrow("unavailable");
  });
  it("reports storage write failure without acknowledging the save",()=>{
    const a=new InviteProposalStorage({getItem:()=>null,setItem:()=>{throw Error("quota");}},"test");a.load(source);expect(()=>a.write(complete())).toThrow("could not save");
  });
  it("checks sample conflicts, unavailable data, account isolation and cancelled requests without network",async()=>{
    vi.useFakeTimers();const network=vi.fn();vi.stubGlobal("fetch",network);
    try {
      const run=async(fields=complete().fields)=>{const promise=sampleInviteCheck(fields,new AbortController().signal);const result=promise.then(v=>v,e=>e);await vi.advanceTimersByTimeAsync(800);return result;};
      expect(await run()).toMatchObject({status:"clear"});
      expect(await run({...complete().fields,start:"2026-10-02T09:30",end:"2026-10-02T10:00"})).toMatchObject({status:"conflict"});
      expect(await run({...complete().fields,accountID:"sample-personal",calendarID:"personal",start:"2026-10-02T09:30",end:"2026-10-02T10:00"})).toMatchObject({status:"clear"});
      expect(await run({...complete().fields,calendarID:"offline"})).toBeInstanceOf(Error);
      const controller=new AbortController(),pending=sampleInviteCheck(complete().fields,controller.signal).catch(e=>e);controller.abort();expect(await pending).toBeInstanceOf(Error);
      expect(network).not.toHaveBeenCalled();
    } finally {vi.unstubAllGlobals();vi.useRealTimers();}
  });
});
