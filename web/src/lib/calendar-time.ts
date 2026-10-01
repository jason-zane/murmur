import dayjs from "./scheduling/dayjs";
export const calendarWallTime=(instant:string,zone:string)=>dayjs(instant).tz(zone).format("YYYY-MM-DDTHH:mm");
export function calendarInstant(value:string,zone:string,original?:string,originalZone?:string) {
 // Preserve the original offset in a repeated local hour when only other fields changed.
 if(original&&zone===originalZone&&calendarWallTime(original,zone)===value)return original;
 const parsed=dayjs.tz(value,zone);
 if(parsed.format("YYYY-MM-DDTHH:mm")!==value)throw new Error("This time does not exist during the daylight-saving change. Choose another time.");
 return parsed.toISOString();
}
