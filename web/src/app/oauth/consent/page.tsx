import { redirect } from "next/navigation";
import Link from "next/link";
import { Brand } from "@/components/brand";
import { serverClient } from "@/lib/supabase/server";
import { Consent } from "./consent";
export const dynamic = "force-dynamic";
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ authorization_id?: string }>;
}) {
  const { authorization_id: id } = await searchParams;
  if (!id)
    return (
      <main id="main" className="consent">
        <Brand />
        <h1>This connection link is incomplete.</h1>
        <Link href="/connections">Return to Connections</Link>
      </main>
    );
  const client = await serverClient();
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user)
    redirect(
      `/login?next=${encodeURIComponent(`/oauth/consent?authorization_id=${encodeURIComponent(id)}`)}`,
    );
  const { data, error } = await client.auth.oauth.getAuthorizationDetails(id);
  if (error || !data)
    return (
      <main id="main" className="consent">
        <Brand />
        <h1>This connection request has expired.</h1>
        <p>Return to your app and connect again.</p>
        <Link href="/connections">Your connections</Link>
      </main>
    );
  if ("redirect_url" in data) redirect(data.redirect_url);
  return (
    <Consent
      details={data}
      email={user.email || ""}
      desktop={data.client.id === process.env.MURMUR_DESKTOP_CLIENT_ID}
    />
  );
}
