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
import { googleReconnection, isReconnectedAccount } from "@/lib/google-reconnect";
export async function GET(request: Request) {
  let bookingFlow = false;
  let mailFlow = false;
  let inboxFlow = false;
  try {
    const { user, client } = await requestAuth(request),
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
      userID?: string;
      booking?: boolean;
      mail?: boolean;
      inbox?: boolean;
      reconnectID?: string;
    };
    bookingFlow = Boolean(expected.booking);
    mailFlow = Boolean(expected.mail);
    inboxFlow = Boolean(expected.inbox);
    const a = Buffer.from(state),
      b = Buffer.from(expected.state);
    if (a.length !== b.length || !timingSafeEqual(a, b))
      throw new Error("This connection request has expired. Please try again.");
    if (!expected.userID || expected.userID !== user.id)
      throw new Error("Your Concourse account changed during connection. Restart from Connected apps in the account you want to use.");
    const reconnect = expected.reconnectID ? await googleReconnection(client, user.id, expected.reconnectID) : null;
    const token = await googleToken({
      grant_type: "authorization_code",
      code,
      redirect_uri: `${siteURL()}/api/google/callback`,
      code_verifier: expected.verifier,
    });
    const granted = token.scope?.split(" ").filter(Boolean) ?? [];
    if (!reconnect && !inboxFlow && !canReadEvents(granted))
      throw new Error("Allow read-only Calendar access to show your agenda.");
    const response = await fetch(
      "https://openidconnect.googleapis.com/v1/userinfo",
      {
        headers: { Authorization: `Bearer ${token.access_token}` },
        signal: AbortSignal.timeout(15000),
      },
    );
    if(!response.ok) throw new Error("Could not confirm this Google account. Try connecting again.");
    const profile=await response.json();
    if(!profile.sub || !profile.email || !profile.email_verified) throw new Error("Connect a verified Google account.");
    if (reconnect && !isReconnectedAccount(reconnect, profile))
      throw new Error("Choose the same Google account to reconnect it. No connection was changed.");
    if (reconnect && reconnect.scopes.filter(scope => scope.startsWith("https://www.googleapis.com/auth/") && !scope.includes("userinfo.")).some(scope => !granted.includes(scope)))
      throw new Error("Google did not restore the account’s existing access. No connection was changed. Try again from Connected apps and review the permissions.");
    if(inboxFlow && !granted.includes("https://www.googleapis.com/auth/gmail.modify")) throw new Error("Allow mailbox access to connect Gmail.");
    const id = await saveConnection(
      user.id,
      profile.email || null,
      granted,
      token.refresh_token,
      profile.sub,
    );
    const connection = (await connectionsFor(user.id)).find((c) => c.id === id);
    if (connection && canReadEvents(connection.scopes))
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
    if (
      mailFlow &&
      !granted.includes("https://www.googleapis.com/auth/gmail.send")
    )
      throw new Error(
        "Allow sending email to use preparation and follow-up messages.",
      );
    return NextResponse.redirect(
      inboxFlow ? `${siteURL()}/mail?connected=google` : mailFlow
        ? `${siteURL()}/connections?connected=email`
        : bookingFlow
          ? `${siteURL()}/scheduling?connected=booking`
          : `${siteURL()}/connections?connected=google`,
    );
  } catch (e) {
    const message =
      e instanceof Error ? e.message : "Could not connect Google Calendar.";
    return NextResponse.redirect(
      `${siteURL()}/${inboxFlow ? "mail" : bookingFlow ? "scheduling" : "connections"}?error=${encodeURIComponent(message)}`,
    );
  }
}
