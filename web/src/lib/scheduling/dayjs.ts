// The same plugin set Cal.diy's scheduling code and tests were written against, minus its
// business-days plugin. See LICENSE-cal.diy in this directory.
import dayjs from "dayjs";
import customParseFormat from "dayjs/plugin/customParseFormat";
import duration from "dayjs/plugin/duration";
import isBetween from "dayjs/plugin/isBetween";
import isToday from "dayjs/plugin/isToday";
import localizedFormat from "dayjs/plugin/localizedFormat";
import minMax from "dayjs/plugin/minMax";
import relativeTime from "dayjs/plugin/relativeTime";
import timezone from "dayjs/plugin/timezone";
import toArray from "dayjs/plugin/toArray";
import utc from "dayjs/plugin/utc";

dayjs.extend(customParseFormat);
dayjs.extend(isBetween);
dayjs.extend(isToday);
dayjs.extend(localizedFormat);
dayjs.extend(relativeTime);
dayjs.extend(utc);
dayjs.extend(timezone);
dayjs.extend(toArray);
dayjs.extend(minMax);
dayjs.extend(duration);

export type Dayjs = dayjs.Dayjs;

/** dayjs keeps the zone name private; Cal.diy reads it the same way. */
export const getTimeZone = (date: Dayjs): string =>
  (date as unknown as { $x: { $timezone: string } }).$x.$timezone;

export default dayjs;
