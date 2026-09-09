import { cloudReady, googleReady, siteURL } from "@/lib/config";
export function GET() {
  return Response.json({
    ready: cloudReady(),
    siteURL: siteURL(),
    supabaseURL: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
    publishableKey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "",
    desktopClientID: process.env.MURMUR_DESKTOP_CLIENT_ID ?? "",
    googleEnabled: googleReady(),
    mcpURL: `${siteURL()}/mcp`,
  });
}
