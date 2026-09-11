import { NextResponse } from "next/server";
import { adminClient, serverClient } from "@/lib/supabase/server";

// Self-serve account deletion. The signed-in cookie session identifies the account; the
// body must repeat its email so a stray request can't do it. Deleting the auth user
// cascades to sessions, revisions, calendar events and credentials, and revokes every
// OAuth grant. Nothing on the person's Mac is touched.
export async function DELETE(request: Request) {
  const client = await serverClient();
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user)
    return NextResponse.json({ error: "Sign in to delete your account." }, { status: 401 });
  const body = await request.json().catch(() => ({}));
  const confirmed = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
  if (!confirmed || confirmed !== (user.email || "").toLowerCase())
    return NextResponse.json(
      { error: "Type your email address exactly to confirm." },
      { status: 400 },
    );
  let admin;
  try {
    admin = adminClient();
  } catch {
    return NextResponse.json(
      { error: "Account deletion isn't configured on this deployment." },
      { status: 503 },
    );
  }
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error)
    return NextResponse.json(
      { error: "Couldn't delete the account. Please try again." },
      { status: 500 },
    );
  await client.auth.signOut({ scope: "local" });
  return NextResponse.json({ ok: true });
}
