import { timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { requestAuth } from "@/lib/http";
import { adminClient } from "@/lib/supabase/server";
import {
  connectionsFor,
  googleToken,
  refreshConnection,
  saveConnection,
} from "@/lib/calendar";
import { canBook, canReadEvents } from "@/lib/google";
import { siteURL } from "@/lib/config";
export async function GET(request: Request) {
  let bookingFlow = false;
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
    const expected = JSON.parse(stored) as {
      state: string;
      verifier: string;
      booking?: boolean;
    };
    bookingFlow = Boolean(expected.booking);
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
    const granted = token.scope?.split(" ").filter(Boolean) ?? [];
    if (!canReadEvents(granted))
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
    const id = await saveConnection(
      user.id,
      profile.email || null,
      granted,
      token.refresh_token,
    );
    const connection = (await connectionsFor(user.id)).find((c) => c.id === id);
    if (connection)
      await refreshConnection(connection).catch(async (error) => {
        await adminClient()
          .from("calendar_connections")
          .update({
            error:
              error instanceof Error ? error.message : "Calendar sync failed.",
          })
          .eq("id", id);
      });
    if (bookingFlow && !canBook(granted))
      throw new Error(
        "Booking needs permission to add events to your calendar and to see when you’re busy. Try again and allow both.",
      );
    return NextResponse.redirect(
      bookingFlow
        ? `${siteURL()}/scheduling?connected=booking`
        : `${siteURL()}/connections?connected=google`,
    );
  } catch (e) {
    const message =
      e instanceof Error ? e.message : "Could not connect Google Calendar.";
    return NextResponse.redirect(
      `${siteURL()}/${bookingFlow ? "scheduling" : "connections"}?error=${encodeURIComponent(message)}`,
    );
  }
}
