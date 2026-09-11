import { redirect } from "next/navigation";
import { cloudReady, siteURL } from "@/lib/config";
import { serverClient } from "@/lib/supabase/server";
import { Connections } from "./settings";
export const dynamic = "force-dynamic";
export default async function Page() {
  if (!cloudReady()) redirect("/login");
  const client = await serverClient();
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) redirect("/login?next=/connections");
  const [connections, sources] = await Promise.all([
    client
      .from("calendar_connections")
      .select("id,email,scopes,updated_at,error,created_at")
      .order("created_at"),
    client
      .from("calendar_sources")
      .select("connection_id,calendar_id,name,color,is_primary,can_write,selected")
      .order("is_primary", { ascending: false })
      .order("name"),
  ]);
  return (
    <Connections
      email={user.email || "Your account"}
      mcpURL={`${siteURL()}/mcp`}
      accounts={connections.data ?? []}
      calendars={sources.data ?? []}
      calendarUnavailable={Boolean(connections.error || sources.error)}
      googleReady={Boolean(
        process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET,
      )}
    />
  );
}
