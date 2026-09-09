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
  const { data } = await client
    .from("calendar_connections")
    .select("email,updated_at,error")
    .maybeSingle();
  return (
    <Connections
      email={user.email || "Your account"}
      mcpURL={`${siteURL()}/mcp`}
      calendar={data}
      googleReady={Boolean(
        process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET,
      )}
    />
  );
}
