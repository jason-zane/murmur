import {describe,it,expect} from "vitest";
import {calendarInstant,calendarWallTime} from "../src/lib/calendar-time";
describe("calendar wall-clock editing",()=>{
 it("rejects a skipped Sydney local hour instead of silently moving the event",()=>{
  expect(()=>calendarInstant("2026-10-04T02:30","Australia/Sydney")).toThrow("does not exist");
  expect(calendarInstant("2026-10-04T03:30","Australia/Sydney")).toBe("2026-10-03T16:30:00.000Z");
 });
 it("preserves either occurrence of a repeated New York hour during a title-only edit",()=>{
  for(const original of ["2026-11-01T05:30:00Z","2026-11-01T06:30:00Z"]){
   const local=calendarWallTime(original,"America/New_York");expect(local).toBe("2026-11-01T01:30");
   expect(calendarInstant(local,"America/New_York",original,"America/New_York")).toBe(original);
  }
 });
});
