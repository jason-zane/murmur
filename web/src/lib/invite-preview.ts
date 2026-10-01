import { inviteInstant,type InviteCalendar,type InviteCheck } from "./invite-proposal";
export const sampleInviteCalendars:InviteCalendar[]=[
  {accountID:"sample-work",accountEmail:"sam@example.com",id:"work",name:"Work calendar · sample"},
  {accountID:"sample-work",accountEmail:"sam@example.com",id:"offline",name:"Travel calendar · sample unavailable"},
  {accountID:"sample-personal",accountEmail:"sam.personal@example.com",id:"personal",name:"Personal calendar · sample"},
];
/** Deliberately isolated fixture adapter: no fetch, AI call, account access or event write. */
export const sampleInviteCheck:InviteCheck=async(fields,signal)=>{
  await new Promise<void>((resolve,reject)=>{
    if(signal.aborted){reject(Error("Check cancelled"));return;}
    const cancel=()=>{clearTimeout(timer);reject(Error("Check cancelled"));};
    const timer=setTimeout(()=>{signal.removeEventListener("abort",cancel);resolve();},800);
    signal.addEventListener("abort",cancel,{once:true});
  });
  if(!sampleInviteCalendars.some(c=>c.accountID===fields.accountID&&c.id===fields.calendarID))throw Error("Unknown sample calendar.");
  if(fields.calendarID==="offline")throw Error("Sample calendar data is unavailable. This does not mean you are free.");
  const start=Date.parse(inviteInstant(fields.start,fields.zone)),end=Date.parse(inviteInstant(fields.end,fields.zone));
  const busyStart=Date.parse("2026-10-01T23:00:00Z"),busyEnd=Date.parse("2026-10-02T00:00:00Z");
  if(fields.accountID==="sample-work"&&start<busyEnd&&end>busyStart)return {status:"conflict",detail:"Sample conflict: Product sync · 2 October, 09:00–10:00 Australia/Sydney. Choose another time and check again."};
  return {status:"clear",detail:"No overlap in this account’s sample busy times. Attendee availability is not checked; nothing is reserved."};
};
