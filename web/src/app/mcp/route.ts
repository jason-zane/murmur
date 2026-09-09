import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { createMCP } from "@/lib/mcp";
import { bearerClient } from "@/lib/supabase/server";
import { cloudReady, siteURL } from "@/lib/config";
import { limitedJSON } from "@/lib/http";
export const runtime = "nodejs";
export const maxDuration = 60;
const metadata = () => `${siteURL()}/.well-known/oauth-protected-resource/mcp`;
export async function POST(request: Request) {
  if (!cloudReady())
    return Response.json(
      { error: "Cloud setup is still being completed." },
      { status: 503 },
    );
  const token = request.headers
    .get("authorization")
    ?.match(/^Bearer (\S+)$/i)?.[1];
  const unauthorized = () =>
    Response.json(
      { error: "Connect your Voice Notes account to read your notes." },
      {
        status: 401,
        headers: {
          "WWW-Authenticate": `Bearer resource_metadata="${metadata()}"`,
          "Cache-Control": "no-store",
        },
      },
    );
  if (!token) return unauthorized();
  const client = bearerClient(token);
  const { data, error } = await client.auth.getClaims(token);
  const claims = data?.claims;
  const audiences = Array.isArray(claims?.aud) ? claims.aud : [claims?.aud];
  if (
    error ||
    !claims?.sub ||
    !claims.client_id ||
    claims.iss !== `${process.env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1` ||
    !audiences.includes(`${siteURL()}/mcp`)
  )
    return unauthorized();
  const origin = request.headers.get("origin");
  if (
    origin &&
    ![
      siteURL(),
      "https://chatgpt.com",
      "https://chat.openai.com",
      "https://claude.ai",
    ].includes(origin)
  )
    return new Response(null, { status: 403 });
  const server = createMCP(client, claims.sub);
  const transport = new WebStandardStreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: true,
  });
  try {
    const parsedBody = await limitedJSON(request, 1_000_000);
    await server.connect(transport);
    const response = await transport.handleRequest(request, { parsedBody });
    response.headers.set("Cache-Control", "no-store");
    return response;
  } catch {
    return Response.json(
      {
        jsonrpc: "2.0",
        error: { code: -32600, message: "Invalid MCP request" },
        id: null,
      },
      { status: 400 },
    );
  } finally {
    await server.close();
  }
}
export function GET() {
  return new Response(null, {
    status: 405,
    headers: {
      Allow: "POST",
      "WWW-Authenticate": `Bearer resource_metadata="${metadata()}"`,
    },
  });
}
export const DELETE = GET;
export function OPTIONS() {
  return new Response(null, {
    status: 204,
    headers: {
      Allow: "POST, OPTIONS",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers":
        "Authorization, Content-Type, MCP-Protocol-Version",
    },
  });
}
