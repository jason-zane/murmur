import { NextResponse } from "next/server";
import { requireEditor, failure, HttpError } from "@/lib/http";
import { adminClient, serverClient } from "@/lib/supabase/server";
import { siteURL } from "@/lib/config";
/** Exchange a trusted app bearer session for an isolated web session. No email is sent,
 * no refresh token is shared with JavaScript, and MCP credentials are rejected. */
export async function POST(request: Request) {
  try {
    if (!request.headers.get("authorization")?.startsWith("Bearer "))
      throw new HttpError(401, "Open this page from the signed-in Mac app.");
    const { user } = await requireEditor(request);
    if (!user.email)
      throw new HttpError(400, "Your account needs an email address.");
    const path = new URL(request.url).searchParams.get("page");
    const destination = ["/scheduling", "/connections"].includes(path || "")
      ? path!
      : "/scheduling";
    const db = adminClient();
    const { data: allowed, error: rateError } = await db.rpc(
      "hit_booking_rate_limit",
      {
        p_bucket: `native-session:${user.id}`,
        p_limit: 60,
        p_window_seconds: 3600,
      },
    );
    if (rateError) throw rateError;
    if (!allowed)
      throw new HttpError(
        429,
        "Please wait a moment before reopening this workspace.",
      );
    const { data, error } = await db.auth.admin.generateLink({
      type: "magiclink",
      email: user.email,
    });
    if (error || !data.properties?.hashed_token || data.user.id !== user.id)
      throw new HttpError(
        503,
        "The shared workspace could not be opened. Try again.",
      );
    const client = await serverClient();
    const { data: session, error: verifyError } = await client.auth.verifyOtp({
      type: "email",
      token_hash: data.properties.hashed_token,
    });
    if (verifyError || session.user?.id !== user.id) {
      await client.auth.signOut({ scope: "local" });
      throw new HttpError(401, "Sign in again to open this workspace.");
    }
    return NextResponse.redirect(`${siteURL()}${destination}`, {
      status: 303,
      headers: {
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      },
    });
  } catch (e) {
    return failure(e);
  }
}
