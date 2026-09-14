import { NextResponse } from "next/server";
import { latestMac } from "@/lib/release";

// One permanent URL to hand out — /api/download/mac always lands on the current disk
// image. Falls through to the release listing if GitHub is unreachable, so the link is
// never dead.
export async function GET() {
  const { download } = await latestMac();
  return NextResponse.redirect(download, 302);
}
