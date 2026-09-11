import { redirect } from "next/navigation";
import { cloudReady } from "@/lib/config";
import { serverClient } from "@/lib/supabase/server";
import { AccountSettings } from "./settings";

export const dynamic = "force-dynamic";

export default async function Page() {
  if (!cloudReady()) redirect("/login");
  const client = await serverClient();
  const { data: { user } } = await client.auth.getUser();
  if (!user) redirect("/login?next=/settings");
  const { data: calendars, error } = await client
    .from("calendar_connections")
    .select("email,updated_at,error")
    .order("created_at");
  return (
    <AccountSettings
      email={user.email || "Your account"}
      calendars={calendars ?? []}
      calendarUnavailable={Boolean(error)}
    />
  );
}
