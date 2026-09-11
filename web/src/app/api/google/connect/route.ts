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
    await requireEditor(request, "Calendar settings require signing in to Voice Notes.");
    if (!process.env.GOOGLE_CLIENT_ID || !process.env.GOOGLE_CLIENT_SECRET)
      throw new HttpError(
        503,
        "Google Calendar setup is still being completed.",
      );
    const params = new URL(request.url).searchParams;
    const booking = params.get("booking") === "1",
      add = params.get("add") === "1",
      account = params.get("account");
    const state = randomBytes(32).toString("base64url"),
      verifier = randomBytes(32).toString("base64url"),
      jar = await cookies();
    jar.set("murmur-google", JSON.stringify({ state, verifier, booking }), {
      httpOnly: true,
      secure: siteURL().startsWith("https:"),
      sameSite: "lax",
      maxAge: 600,
      path: "/api/google/callback",
    });
    const q = new URLSearchParams({
      client_id: process.env.GOOGLE_CLIENT_ID,
      redirect_uri: `${siteURL()}/api/google/callback`,
      response_type: "code",
      scope: (booking ? BOOKING_SCOPES : READ_SCOPES).join(" "),
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
    return failure(e);
  }
}
