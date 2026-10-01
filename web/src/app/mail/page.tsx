import { redirect } from "next/navigation";
import { cloudReady } from "@/lib/config";
import { serverClient } from "@/lib/supabase/server";
import { MailWorkspace } from "@/components/mail-workspace";
export const dynamic="force-dynamic";
export default async function Page() {
 if(!cloudReady()) redirect("/login");
 const {data:{user}}=await (await serverClient()).auth.getUser();
 if(!user) redirect("/login?next=/mail");
 return <MailWorkspace email={user.email || "Your account"} userID={user.id} googleReady={Boolean(process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET)}/>;
}
