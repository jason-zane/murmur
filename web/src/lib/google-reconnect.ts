import type { SupabaseClient } from "@supabase/supabase-js";
import { HttpError } from "./http";

/** Read through the authenticated client and bind recovery to its owner and provider. */
export async function googleReconnection(client: SupabaseClient, userID: string, id: string) {
  const { data, error } = await client.from("calendar_connections")
    .select("id,email,provider_subject,scopes")
    .eq("user_id", userID).eq("provider", "google").eq("id", id).maybeSingle();
  if (error) throw error;
  if (!data || !data.scopes?.length || (!data.provider_subject && !data.email))
    throw new HttpError(404, "This Google account is no longer linked. Return to Connected apps and choose an account.");
  return data as { id: string; email: string | null; provider_subject: string | null; scopes: string[] };
}

export function isReconnectedAccount(
  account: { email: string | null; provider_subject: string | null },
  profile: { sub: string; email: string },
) {
  return account.provider_subject
    ? account.provider_subject === profile.sub
    : account.email?.toLowerCase() === profile.email.toLowerCase();
}
