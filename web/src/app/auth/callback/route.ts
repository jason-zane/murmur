import { NextResponse } from "next/server";
import { serverClient } from "@/lib/supabase/server";
import { safeNext, siteURL } from "@/lib/config";
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const code = params.get("code");
  if (code) {
    const client = await serverClient();
    const { error } = await client.auth.exchangeCodeForSession(code);
    if (!error)
      return NextResponse.redirect(
        new URL(safeNext(params.get("next")), siteURL()),
      );
  }
  return NextResponse.redirect(
    new URL(
      "/login?error=Sign-in%20expired.%20Please%20try%20again.",
      siteURL(),
    ),
  );
}
