import {describe,it,expect} from "vitest";
import {validCalendarNotification} from "../src/lib/calendar-push";
const channel={id:"00000000-0000-4000-8000-000000000001",token:"secret-random-channel-token",resource_id:"calendar-resource",expires_at:"2026-10-01T00:00:00Z"};
const now=Date.parse("2026-09-30T00:00:00Z");
const headers=()=>new Headers({"x-goog-channel-id":channel.id,"x-goog-channel-token":channel.token,"x-goog-resource-id":channel.resource_id,"x-goog-resource-state":"exists"});
describe("calendar notification verification",()=>{
 it("accepts only the channel, secret and exact resource within its lifetime",()=>{
  expect(validCalendarNotification(headers(),channel,now)).toBe(true);
  for(const key of ["x-goog-channel-id","x-goog-channel-token","x-goog-resource-id","x-goog-resource-state"]){const invalid=headers();invalid.set(key,"another-value");expect(validCalendarNotification(invalid,channel,now)).toBe(false);}
  expect(validCalendarNotification(headers(),channel,Date.parse(channel.expires_at))).toBe(false);
 });
 it("supports initial sync before the registration response without trusting a missing secret",()=>{
  const initial=headers();initial.set("x-goog-resource-state","sync");
  expect(validCalendarNotification(initial,{...channel,resource_id:null},now)).toBe(true);
  initial.delete("x-goog-channel-token");expect(validCalendarNotification(initial,{...channel,resource_id:null},now)).toBe(false);
 });
});
