import { redirect } from "next/navigation";
import { cloudReady, googleReady } from "@/lib/config";
import { serverClient } from "@/lib/supabase/server";
import { Scheduling } from "./scheduling";
export const dynamic = "force-dynamic";
export default async function Page() {
  if (!cloudReady()) redirect("/login");
  const client = await serverClient();
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) redirect("/login?next=/scheduling");
  return (
    <Scheduling
      email={user.email || "Your account"}
      googleReady={googleReady() || Boolean(process.env.GOOGLE_CLIENT_ID)}
    />
  );
}
