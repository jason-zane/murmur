import { randomBytes, createHash } from "node:crypto";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { z } from "zod";
import { requireEditor, failure, HttpError } from "@/lib/http";
import { siteURL } from "@/lib/config";
import { BOOKING_SCOPES, READ_SCOPES } from "@/lib/google";
// ?add=1 lets someone choose a different Google account. ?booking=1 asks for the two extra
// permissions booking needs, for the account named in ?account=.
export async function GET(request: Request) {
  try {
    const { user } = await requireEditor(
      request,
      "Calendar settings require signing in to Concourse.",
    );
    if (!process.env.GOOGLE_CLIENT_ID || !process.env.GOOGLE_CLIENT_SECRET)
      throw new HttpError(
        503,
        "Google Calendar setup is still being completed.",
      );
    const params = new URL(request.url).searchParams;
    const expectedUser = params.get("expected_user");
    if (expectedUser && expectedUser !== user.id) {
      return NextResponse.redirect(new URL("/connections?error=" + encodeURIComponent("This browser is signed in to a different Concourse account from your Mac. Sign out in Account settings, then sign in to the same account before connecting Google."), siteURL()));
    }
    const inbox=params.get("inbox")==="1";
    const mail = params.get("mail") === "1";
    const booking = params.get("booking") === "1",
      add = params.get("add") === "1",
      account = params.get("account");
    const state = randomBytes(32).toString("base64url"),
      verifier = randomBytes(32).toString("base64url"),
      jar = await cookies();
    jar.set(
      "murmur-google",
      JSON.stringify({ state, verifier, userID: user.id, booking, mail, inbox }),
      {
        httpOnly: true,
        secure: siteURL().startsWith("https:"),
        sameSite: "lax",
        maxAge: 600,
        path: "/api/google/callback",
      },
    );
    const q = new URLSearchParams({
      client_id: process.env.GOOGLE_CLIENT_ID,
      redirect_uri: `${siteURL()}/api/google/callback`,
      response_type: "code",
      scope: [
        ...(inbox ? ["openid","email","https://www.googleapis.com/auth/gmail.modify"] : booking ? BOOKING_SCOPES : READ_SCOPES),
        ...(mail ? ["https://www.googleapis.com/auth/gmail.send"] : []),
      ].join(" "),
      access_type: "offline",
      prompt: add ? "consent select_account" : "consent",
      include_granted_scopes: "true",
      state,
      code_challenge: createHash("sha256").update(verifier).digest("base64url"),
      code_challenge_method: "S256",
      ...(account && z.email().safeParse(account).success
        ? { login_hint: account }
        : {}),
    });
    return NextResponse.redirect(
      `https://accounts.google.com/o/oauth2/v2/auth?${q}`,
    );
  } catch (e) {
    if (e instanceof HttpError && e.status === 401 && !request.headers.has("authorization")) {
      const params = new URL(request.url).searchParams;
      const next = "/api/google/connect" + (params.size ? `?${params}` : "");
      return NextResponse.redirect(new URL(`/login?next=${encodeURIComponent(next)}`, siteURL()));
    }
    return failure(e);
  }
}
