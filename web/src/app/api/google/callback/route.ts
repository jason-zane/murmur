import { timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { requestAuth } from "@/lib/http";
import { adminClient } from "@/lib/supabase/server";
import { googleToken, encryptToken, refreshCalendar } from "@/lib/calendar";
import { siteURL } from "@/lib/config";
export async function GET(request: Request) {
  try {
    const { user } = await requestAuth(request),
      params = new URL(request.url).searchParams,
      jar = await cookies(),
      stored = jar.get("murmur-google")?.value;
    jar.delete({ name: "murmur-google", path: "/api/google/callback" });
    const state = params.get("state"),
      code = params.get("code");
    if (!stored || !state || !code)
      throw new Error(
        "Calendar connection was cancelled or expired. Please try again.",
      );
    const expected = JSON.parse(stored);
    const a = Buffer.from(state),
      b = Buffer.from(expected.state);
    if (a.length !== b.length || !timingSafeEqual(a, b))
      throw new Error("This connection request has expired. Please try again.");
    const token = await googleToken({
      grant_type: "authorization_code",
      code,
      redirect_uri: `${siteURL()}/api/google/callback`,
      code_verifier: expected.verifier,
    });
    if (
      !token.scope
        ?.split(" ")
        .some(
          (s) =>
            s === "https://www.googleapis.com/auth/calendar.events.readonly" ||
            s === "https://www.googleapis.com/auth/calendar.readonly",
        )
    )
      throw new Error("Allow read-only Calendar access to show your agenda.");
    if (!token.refresh_token)
      throw new Error(
        "Google did not provide offline access. Reconnect and allow Calendar access.",
      );
    const response = await fetch(
      "https://openidconnect.googleapis.com/v1/userinfo",
      {
        headers: { Authorization: `Bearer ${token.access_token}` },
        signal: AbortSignal.timeout(15000),
      },
    );
    const profile = response.ok ? await response.json() : {};
    const db = adminClient();
    const { error } = await db
      .from("calendar_credentials")
      .upsert({
        user_id: user.id,
        encrypted_refresh_token: encryptToken(token.refresh_token),
        updated_at: new Date().toISOString(),
      });
    if (error) throw error;
    const { error: statusError } = await db
      .from("calendar_connections")
      .upsert({
        user_id: user.id,
        email: profile.email || null,
        error: null,
        updated_at: null,
      });
    if (statusError) throw statusError;
    await refreshCalendar(user.id, true);
    return NextResponse.redirect(`${siteURL()}/connections?connected=google`);
  } catch (e) {
    const message =
      e instanceof Error ? e.message : "Could not connect Google Calendar.";
    return NextResponse.redirect(
      `${siteURL()}/connections?error=${encodeURIComponent(message)}`,
    );
  }
}
