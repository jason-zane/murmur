import { z } from "zod";
import { calendarInstant, calendarWallTime } from "./calendar-time";

export type InviteSource = { accountID:string; mailbox:string; messageID:string; subject:string; from:string; sentAt:string; text:string; evidence:string };
export type InviteCalendar = { accountID:string; accountEmail:string; id:string; name:string };
const fieldsSchema=z.object({title:z.string(),accountID:z.string(),calendarID:z.string(),start:z.string(),end:z.string(),zone:z.string(),guests:z.string()}).strict();
export type InviteFields=z.infer<typeof fieldsSchema>;
const availabilitySchema=z.object({signature:z.string(),status:z.enum(["clear","conflict","unavailable"]),detail:z.string(),checkedAt:z.number()}).strict();
export type InviteAvailability=z.infer<typeof availabilitySchema>;
const proposalSchema=z.object({version:z.literal(1),sourceStamp:z.string(),fields:fieldsSchema,availability:availabilitySchema.nullable(),reviewed:z.boolean()}).strict();
export type InviteProposal=z.infer<typeof proposalSchema>;
export type InviteCheck=(fields:InviteFields,signal:AbortSignal)=>Promise<Omit<InviteAvailability,"signature"|"checkedAt">>;
export const sourceStamp=(source:InviteSource)=>JSON.stringify(source);
export const proposalKey=(userID:string,source:InviteSource)=>`concourse:invite:v1:${encodeURIComponent(userID)}:${encodeURIComponent(source.accountID)}:${encodeURIComponent(source.messageID)}`;
export const availabilitySignature=(fields:InviteFields)=>JSON.stringify([fields.accountID,fields.calendarID,fields.start,fields.end,fields.zone]);
export function newProposal(source:InviteSource):InviteProposal {
  if(!source.evidence.trim()||!source.text.includes(source.evidence))throw Error("Invitation evidence must quote the source email exactly.");
  return {version:1,sourceStamp:sourceStamp(source),fields:{title:source.subject,accountID:source.accountID,calendarID:"",start:"",end:"",zone:"",guests:""},availability:null,reviewed:false};
}
export function editProposal(proposal:InviteProposal,patch:Partial<InviteFields>):InviteProposal {
  const fields={...proposal.fields,...patch};
  return {...proposal,fields,reviewed:false,availability:availabilitySignature(fields)===availabilitySignature(proposal.fields)?proposal.availability:null};
}
export function acceptAvailability(proposal:InviteProposal,signature:string,result:Omit<InviteAvailability,"signature"|"checkedAt">,now:number):InviteProposal {
  if(signature!==availabilitySignature(proposal.fields))return proposal;
  return {...proposal,reviewed:false,availability:{...result,signature,checkedAt:now}};
}
export function inviteInstant(value:string,zone:string):string {
  const instant=calendarInstant(value,zone);
  // New invitations cannot silently choose one occurrence of a repeated local hour.
  for(const minutes of [-120,-60,-30,30,60,120]) {
    if(calendarWallTime(new Date(Date.parse(instant)+minutes*60000).toISOString(),zone)===value)
      throw Error("This time occurs twice during the daylight-saving change. Choose an unambiguous time.");
  }
  return instant;
}
export function proposalProblems(proposal:InviteProposal,calendars:InviteCalendar[]):string[] {
  const f=proposal.fields,problems:string[]=[];
  if(!f.title.trim())problems.push("Add a meeting title.");
  if(!calendars.some(c=>c.accountID===f.accountID&&c.id===f.calendarID))problems.push("Choose the account and destination calendar.");
  if(!f.start)problems.push("Confirm the exact start date and time; the email is tentative.");
  if(!f.end)problems.push("Confirm when the meeting ends; no duration was agreed.");
  if(!f.zone)problems.push("Confirm the time zone; it is missing from the email.");
  if(f.zone) {
    try {
      new Intl.DateTimeFormat("en",{timeZone:f.zone});
      if(f.start&&f.end&&Date.parse(inviteInstant(f.end,f.zone))<=Date.parse(inviteInstant(f.start,f.zone)))problems.push("The meeting must end after it starts.");
      else { if(f.start)inviteInstant(f.start,f.zone);if(f.end)inviteInstant(f.end,f.zone); }
    } catch(e) { problems.push(e instanceof RangeError?"Choose a valid IANA time zone, such as Australia/Sydney.":e instanceof Error?e.message:"Check the meeting times."); }
  }
  const guests=f.guests.split(/[,;]/).map(v=>v.trim()).filter(Boolean);
  if(!guests.length)problems.push("Confirm attendee email addresses; nobody is invited automatically.");
  else if(guests.some(g=>! /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(g)))problems.push("Use valid attendee email addresses, separated by commas.");
  else if(new Set(guests.map(g=>g.toLowerCase())).size!==guests.length)problems.push("Remove duplicate attendee addresses.");
  return problems;
}
export function reviewProposal(proposal:InviteProposal,calendars:InviteCalendar[],now:number):InviteProposal {
  const problems=proposalProblems(proposal,calendars);
  if(problems.length)throw Error(problems[0]);
  const check=proposal.availability;
  if(!check||check.signature!==availabilitySignature(proposal.fields)||now-check.checkedAt>600000||now<check.checkedAt)throw Error("Check sample availability again before reviewing.");
  if(check.status!=="clear")throw Error(check.status==="conflict"?"Resolve the sample conflict before reviewing.":"Availability is unavailable. Your proposal is still saved locally.");
  if(proposal.reviewed)return proposal;
  return {...proposal,reviewed:true};
}
/** One local object per mailbox/message. Fail closed on corrupt storage or another tab's edits. */
export class InviteProposalStorage {
  private baseline:string|null=null;
  private loaded=false;
  constructor(private storage:Pick<Storage,"getItem"|"setItem">|undefined,private key:string) {}
  load(source:InviteSource):{proposal:InviteProposal;sourceChanged:boolean;restored:boolean} {
    newProposal(source); // Verify the evidence before associating saved edits with this source.
    if(!this.storage)throw Error("Browser storage is unavailable. Keep this review open to retain edits.");
    let proposal:InviteProposal;
    try {this.baseline=this.storage.getItem(this.key);proposal=this.baseline?proposalSchema.parse(JSON.parse(this.baseline)):newProposal(source);}
    catch {throw Error("Saved proposal could not be read. Its original data has been preserved.");}
    this.loaded=true;
    const sourceChanged=proposal.sourceStamp!==sourceStamp(source);
    return {proposal:sourceChanged?{...proposal,sourceStamp:sourceStamp(source),reviewed:false,availability:null}:proposal,sourceChanged,restored:Boolean(this.baseline)};
  }
  write(proposal:InviteProposal) {
    if(!this.storage||!this.loaded)throw Error("Saved proposal could not be read. Keep your edits open; the original data is preserved.");
    if(this.storage.getItem(this.key)!==this.baseline)throw Error("This proposal changed in another tab. Keep your edits open and reopen before replacing them.");
    const next=JSON.stringify(proposalSchema.parse(proposal));
    if(next===this.baseline)return;
    try {this.storage.setItem(this.key,next);}catch {throw Error("This browser could not save your edits. Keep the review open.");}
    this.baseline=next;
  }
}
