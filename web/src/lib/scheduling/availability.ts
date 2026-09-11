import { buildDateRanges, subtract, type DateOverride, type WorkingHours } from "./date-ranges";
import dayjs from "./dayjs";
import getSlots from "./slots";

/** Weekdays use 0 for Sunday. Times are "HH:MM"; "24:00" means the end of the day. */
export type WeeklyHours = { days: number[]; start: string; end: string }[];
/** A date with no ranges is a day off. Dates are YYYY-MM-DD in the host's time zone. */
export type DateOverrides = { date: string; ranges: { start: string; end: string }[] }[];
export type Interval = { start: Date; end: Date };

export type SlotRules = {
  timeZone: string;
  weeklyHours: WeeklyHours;
  dateOverrides: DateOverrides;
  durationMinutes: number;
  slotIntervalMinutes?: number | null;
  minimumNoticeMinutes: number;
  bufferBeforeMinutes: number;
  bufferAfterMinutes: number;
  bookingWindowDays: number;
  dailyLimit?: number | null;
};

const clock = (value: string) => {
  const [h, m] = value === "24:00" ? [23, 59] : value.split(":").map(Number);
  return new Date(Date.UTC(1970, 0, 1, h, m));
};

/** Cal.diy's engine stores times as the UTC hours of a Date, and a day off as 00:00–00:00. */
export function toAvailability(weekly: WeeklyHours, overrides: DateOverrides) {
  const items: (WorkingHours | DateOverride)[] = weekly.map((w) => ({
    days: w.days,
    startTime: clock(w.start),
    endTime: clock(w.end),
  }));
  for (const o of overrides) {
    const date = new Date(`${o.date}T00:00:00Z`);
    if (!o.ranges.length) items.push({ date, startTime: clock("00:00"), endTime: clock("00:00") });
    for (const r of o.ranges) items.push({ date, startTime: clock(r.start), endTime: clock(r.end) });
  }
  return items;
}

/**
 * Bookable start times in [from, to). Busy intervals come from every counted calendar and
 * from existing bookings. A slot needs its buffers clear of other commitments: a busy block
 * is widened by the after-buffer on its left and the before-buffer on its right.
 */
export function availableSlots(
  rules: SlotRules,
  {
    from,
    to,
    busy,
    inviteeTimeZone,
    bookedStartsOfType = [],
    now = new Date(),
  }: {
    from: Date;
    to: Date;
    busy: Interval[];
    inviteeTimeZone: string;
    bookedStartsOfType?: Date[];
    now?: Date;
  },
): Date[] {
  const start = Math.max(from.getTime(), now.getTime());
  const end = Math.min(to.getTime(), now.getTime() + rules.bookingWindowDays * 86_400_000);
  if (end <= start) return [];
  const { dateRanges } = buildDateRanges({
    availability: toAvailability(rules.weeklyHours, rules.dateOverrides),
    timeZone: rules.timeZone,
    dateFrom: dayjs(start),
    dateTo: dayjs(end),
    travelSchedules: [],
  });
  const blocked = busy.map((b) => ({
    start: dayjs(b.start.getTime() - rules.bufferAfterMinutes * 60_000),
    end: dayjs(b.end.getTime() + rules.bufferBeforeMinutes * 60_000),
  }));
  const free = subtract(dateRanges, blocked);
  const perDay = new Map<string, number>();
  for (const booked of bookedStartsOfType) {
    const day = dayjs(booked).tz(rules.timeZone).format("YYYY-MM-DD");
    perDay.set(day, (perDay.get(day) ?? 0) + 1);
  }
  const length = rules.durationMinutes * 60_000;
  return getSlots({
    inviteeDate: dayjs().tz(inviteeTimeZone),
    frequency: rules.slotIntervalMinutes || rules.durationMinutes,
    minimumBookingNotice: rules.minimumNoticeMinutes,
    dateRanges: free,
    eventLength: rules.durationMinutes,
  })
    .map((slot) => slot.time.toDate())
    .filter((slot) => slot.getTime() >= start && slot.getTime() + length <= end)
    .filter(
      (slot) =>
        !rules.dailyLimit ||
        (perDay.get(dayjs(slot).tz(rules.timeZone).format("YYYY-MM-DD")) ?? 0) < rules.dailyLimit,
    )
    .sort((a, b) => a.getTime() - b.getTime());
}

/** The exact start must still be offered when the guest confirms. */
export function isSlotAvailable(
  rules: SlotRules,
  slot: Date,
  context: Omit<Parameters<typeof availableSlots>[1], "from" | "to">,
) {
  return availableSlots(rules, {
    ...context,
    from: new Date(slot.getTime() - 86_400_000),
    to: new Date(slot.getTime() + (rules.durationMinutes + 1440) * 60_000),
  }).some((s) => s.getTime() === slot.getTime());
}

export function isTimeZone(value: string) {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value });
    return value.length <= 64;
  } catch {
    return false;
  }
}
