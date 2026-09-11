import { redirect } from "next/navigation";
import { cloudReady } from "@/lib/config";
import { serverClient } from "@/lib/supabase/server";
import { ResetPassword } from "./reset";

export const dynamic = "force-dynamic";

// The recovery link lands on /auth/callback, which exchanges the code for a session and
// sends the browser here. Only a signed-in session can set a password.
export default async function Page() {
  if (!cloudReady()) redirect("/login");
  const client = await serverClient();
  const { data: { user } } = await client.auth.getUser();
  if (!user) redirect("/login?error=Reset%20link%20expired.%20Request%20a%20new%20one.");
  return <ResetPassword email={user.email || ""} />;
}
