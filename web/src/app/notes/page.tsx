import { redirect } from "next/navigation";
import { cloudReady } from "@/lib/config";
import { serverClient } from "@/lib/supabase/server";
import { Library } from "@/components/library";
export const dynamic = "force-dynamic";
export default async function Page() {
  if (!cloudReady()) redirect("/login");
  const client = await serverClient();
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) redirect("/login");
  return <Library email={user.email || "Your account"} userID={user.id} />;
}
