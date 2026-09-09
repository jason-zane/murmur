import { siteURL } from "@/lib/config";
export function GET() {
  return Response.json(
    {
      resource: `${siteURL()}/mcp`,
      authorization_servers: [
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1`,
      ],
      scopes_supported: ["openid", "email", "profile"],
      bearer_methods_supported: ["header"],
      resource_name: "Voice Notes library",
      resource_documentation: `${siteURL()}/connections`,
    },
    { headers: { "Access-Control-Allow-Origin": "*" } },
  );
}
