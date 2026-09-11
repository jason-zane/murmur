import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { availableSlots, isSlotAvailable, isTimeZone, type SlotRules } from "@/lib/scheduling/availability";
import dayjs from "@/lib/scheduling/dayjs";

// Monday 14 September 2026, 10:00 in Sydney (UTC+10 until daylight saving on 4 October).
const now = new Date("2026-09-14T00:00:00Z");
const rules: SlotRules = {
  timeZone: "Australia/Sydney",
  weeklyHours: [{ days: [1, 2, 3, 4, 5], start: "09:00", end: "17:00" }],
  dateOverrides: [],
  durationMinutes: 30,
  minimumNoticeMinutes: 0,
  bufferBeforeMinutes: 0,
  bufferAfterMinutes: 0,
  bookingWindowDays: 60,
};
const tuesday = { from: new Date("2026-09-14T14:00:00Z"), to: new Date("2026-09-15T14:00:00Z") };
const local = (d: Date) => dayjs(d).tz("Australia/Sydney").format("ddd HH:mm");
const slots = (overrides: Partial<SlotRules> = {}, context: Partial<Parameters<typeof availableSlots>[1]> = {}) =>
  availableSlots({ ...rules, ...overrides }, { ...tuesday, busy: [], inviteeTimeZone: "Australia/Sydney", now, ...context }).map(local);
const at = (value: string) => new Date(value);

describe("booking availability", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(now);
  });
  afterEach(() => vi.useRealTimers());

  it("offers each half hour of the host's working day in their own time zone", () => {
    const result = slots();
    expect(result).toHaveLength(16);
    expect(result[0]).toBe("Tue 09:00");
    expect(result.at(-1)).toBe("Tue 16:30");
  });

  it("removes busy time from every calendar, including its buffers", () => {
    const busy = [{ start: at("2026-09-15T00:00:00Z"), end: at("2026-09-15T01:00:00Z") }]; // 10:00–11:00
    expect(slots({}, { busy })).not.toContain("Tue 10:00");
    expect(slots({}, { busy })).not.toContain("Tue 10:30");
    expect(slots({}, { busy })).toContain("Tue 11:00");
    const before = slots({ bufferBeforeMinutes: 15 }, { busy });
    expect(before).not.toContain("Tue 11:00");
    expect(before).toContain("Tue 11:30");
    const after = slots({ bufferAfterMinutes: 15 }, { busy });
    expect(after).not.toContain("Tue 09:30");
    expect(after).toContain("Tue 09:00");
  });

  it("respects minimum notice, the booking window and weekends", () => {
    const monday = slots({ minimumNoticeMinutes: 240 }, { from: now, to: at("2026-09-14T14:00:00Z") });
    expect(monday[0]).toBe("Mon 14:00");
    expect(monday).toHaveLength(6);
    expect(slots({ bookingWindowDays: 1 })).toEqual(["Tue 09:00", "Tue 09:30"]);
    expect(slots({}, { from: at("2026-09-18T14:00:00Z"), to: at("2026-09-19T14:00:00Z") })).toEqual([]);
  });

  it("applies date overrides for days off and different hours", () => {
    expect(slots({ dateOverrides: [{ date: "2026-09-15", ranges: [] }] })).toEqual([]);
    expect(slots({ dateOverrides: [{ date: "2026-09-15", ranges: [{ start: "13:00", end: "14:00" }] }] })).toEqual([
      "Tue 13:00",
      "Tue 13:30",
    ]);
  });

  it("stops offering a meeting type once its daily limit is reached", () => {
    const booked = [at("2026-09-15T02:00:00Z")];
    expect(slots({ dailyLimit: 1 }, { bookedStartsOfType: booked })).toEqual([]);
    expect(slots({ dailyLimit: 2 }, { bookedStartsOfType: booked })).toHaveLength(16);
  });

  it("follows daylight saving and offers the same instants to guests elsewhere", () => {
    const dst = availableSlots(rules, {
      from: at("2026-10-04T13:00:00Z"),
      to: at("2026-10-05T13:00:00Z"),
      busy: [],
      inviteeTimeZone: "America/New_York",
      now,
    });
    expect(dst[0]?.toISOString()).toBe("2026-10-04T22:00:00.000Z");
    const kolkata = availableSlots(rules, { ...tuesday, busy: [], inviteeTimeZone: "Asia/Kolkata", now });
    expect(kolkata.map(local)).toEqual(slots());
  });

  it("supports a full day and longer meetings on a quarter-hour grid", () => {
    const day = slots({ weeklyHours: [{ days: [2], start: "00:00", end: "24:00" }] });
    expect(day.at(-1)).toBe("Tue 23:30");
    const long = slots({ durationMinutes: 45, slotIntervalMinutes: 15 });
    expect(long[1]).toBe("Tue 09:15");
    expect(long.at(-1)).toBe("Tue 16:15");
  });

  it("confirms only an exact start that is still free", () => {
    const context = { busy: [{ start: at("2026-09-15T00:00:00Z"), end: at("2026-09-15T01:00:00Z") }], inviteeTimeZone: "UTC", now };
    expect(isSlotAvailable(rules, at("2026-09-14T23:00:00Z"), context)).toBe(true);
    expect(isSlotAvailable(rules, at("2026-09-14T23:10:00Z"), context)).toBe(false);
    expect(isSlotAvailable(rules, at("2026-09-15T00:00:00Z"), context)).toBe(false);
    expect(isSlotAvailable(rules, at("2026-09-13T23:00:00Z"), context)).toBe(false);
  });

  it("recognises real time zones only", () => {
    expect(isTimeZone("Australia/Sydney")).toBe(true);
    expect(isTimeZone("Mars/Olympus_Mons")).toBe(false);
  });
});
