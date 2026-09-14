import type { SupabaseClient } from "@supabase/supabase-js";
import { adminClient } from "../supabase/server";
import { HttpError } from "../http";
import type { Profile, EventType } from "./schema";
/** Keep the public identity, replace only this meeting type's schedule/destination. */
export async function effectiveProfile(
  profile: Profile,
  type: EventType,
): Promise<Profile> {
  let availability = type.availability_override;
  if (type.availability_schedule_id) {
    const { data, error } = await adminClient()
      .from("availability_schedules")
      .select("time_zone,weekly_hours,date_overrides")
      .eq("id", type.availability_schedule_id)
      .eq("user_id", profile.user_id)
      .maybeSingle();
    if (error) throw error;
    if (!data)
      throw new HttpError(
        409,
        "This meeting’s availability needs attention. Contact the host.",
      );
    availability = data;
  }
  return {
    ...profile,
    ...(availability || {}),
    ...(type.destination_connection_id
      ? {
          destination_connection_id: type.destination_connection_id,
          destination_calendar_id: type.destination_calendar_id!,
        }
      : {}),
  };
}
export async function validateTypeReferences(
  client: SupabaseClient,
  type: EventType | Omit<EventType, "id" | "user_id">,
) {
  if (type.email_connection_id) {
    const { data, error } = await client
      .from("calendar_connections")
      .select("scopes")
      .eq("id", type.email_connection_id)
      .maybeSingle();
    if (error) throw error;
    if (!data?.scopes?.includes("https://www.googleapis.com/auth/gmail.send"))
      throw new HttpError(
        400,
        "Choose an email account that has allowed sending.",
      );
  }
  if (type.availability_schedule_id) {
    const { data, error } = await client
      .from("availability_schedules")
      .select("id")
      .eq("id", type.availability_schedule_id)
      .maybeSingle();
    if (error) throw error;
    if (!data)
      throw new HttpError(400, "Choose one of your availability schedules.");
  }
  if (type.destination_connection_id) {
    const { data, error } = await client
      .from("calendar_sources")
      .select("can_write")
      .eq("connection_id", type.destination_connection_id)
      .eq("calendar_id", type.destination_calendar_id!)
      .maybeSingle();
    if (error) throw error;
    if (!data?.can_write)
      throw new HttpError(400, "Choose a calendar you can add meetings to.");
  }
}
