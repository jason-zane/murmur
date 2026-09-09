import { randomBytes, createHash } from "node:crypto";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { requestAuth, failure, HttpError } from "@/lib/http";
import { siteURL } from "@/lib/config";
export async function GET(request: Request) {
  try {
    const { client } = await requestAuth(request);
    const { data: editor } = await client.rpc("is_murmur_editor");
    if (!editor)
      throw new HttpError(
        403,
        "Calendar settings require signing in to Voice Notes.",
      );
    if (!process.env.GOOGLE_CLIENT_ID || !process.env.GOOGLE_CLIENT_SECRET)
      throw new HttpError(
        503,
        "Google Calendar setup is still being completed.",
      );
    const state = randomBytes(32).toString("base64url"),
      verifier = randomBytes(32).toString("base64url"),
      jar = await cookies();
    jar.set("murmur-google", JSON.stringify({ state, verifier }), {
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
      scope:
        "openid email https://www.googleapis.com/auth/calendar.events.readonly",
      access_type: "offline",
      prompt: "consent",
      include_granted_scopes: "true",
      state,
      code_challenge: createHash("sha256").update(verifier).digest("base64url"),
      code_challenge_method: "S256",
    });
    return NextResponse.redirect(
      `https://accounts.google.com/o/oauth2/v2/auth?${q}`,
    );
  } catch (e) {
    return failure(e);
  }
}
