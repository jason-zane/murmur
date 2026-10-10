import {describe,it,expect} from "vitest";
import {workspaceEvent,eventIdentity,rangeSchema,eventInput} from "../src/lib/calendar-workspace";
describe("complete calendar model",()=>{
 it("retains all-day dates in the source zone across Sydney daylight saving",()=>{
  const e=workspaceEvent({id:"holiday",start:{date:"2026-10-04"},end:{date:"2026-10-05"}},"a","c","Australia/Sydney")!;
  expect(e.details.all_day).toBe(true);expect(e.starts_at).toBe("2026-10-03T14:00:00.000Z");expect(e.ends_at).toBe("2026-10-04T13:00:00.000Z");
 });
 it("retains declined and free events for display, not call detection",()=>{
  const e=workspaceEvent({id:"free",start:{dateTime:"2026-10-01T10:00:00Z"},end:{dateTime:"2026-10-01T11:00:00Z"},transparency:"transparent",attendees:[{self:true,responseStatus:"declined"}]},"a","c")!;
  expect(e.details.response).toBe("declined");expect(e.details.availability).toBe("transparent");
 });
 it("keeps provider IDs distinct between accounts and calendars",()=>{
  expect(new Set([eventIdentity("a","c","id"),eventIdentity("b","c","id"),eventIdentity("a","d","id")]).size).toBe(3);
 });
 it("keeps provider reminders and rejects overrides outside Google's limits",()=>{
  const event=workspaceEvent({id:"reminded",start:{dateTime:"2026-10-01T10:00:00Z"},end:{dateTime:"2026-10-01T11:00:00Z"},reminders:{useDefault:false,overrides:[{method:"popup",minutes:30}]}},"a","c")!;
  expect(event.details.reminders?.overrides?.[0].minutes).toBe(30);
  const input={connection_id:"00000000-0000-4000-8000-000000000000",calendar_id:"c",title:"x",start:"2026-01-01",end:"2026-01-02",all_day:true,time_zone:"Australia/Sydney",reminders:{useDefault:false,overrides:[{method:"popup",minutes:40321}]}};
  expect(eventInput.safeParse(input).success).toBe(false);
 });
 it("rejects invalid ranges and times",()=>{
  expect(rangeSchema.safeParse({from:"2026-01-01T00:00:00Z",to:"2027-01-01T00:00:00Z"}).success).toBe(false);
  expect(eventInput.safeParse({connection_id:"00000000-0000-4000-8000-000000000000",calendar_id:"c",title:"x",start:"2026-01-01",end:"2026-01-01",all_day:true,time_zone:"Australia/Sydney"}).success).toBe(false);
 });
});
