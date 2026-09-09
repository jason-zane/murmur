# Voice Notes cloud

The macOS app remains the recording and dictation engine. Its plain-file library works
offline. The hosted Next.js companion on Vercel stores an account-owned copy in Supabase,
provides Google authentication/calendar access, and exposes a read-only remote MCP URL.

## Trust and authentication

Web sign-in uses Supabase Auth and PKCE. The native app uses the same OAuth 2.1 server,
with a registered public desktop client, a custom-scheme callback, PKCE S256 and state.
Its refresh token lives in the macOS Keychain. No service key ships with the Mac app.
Third-party MCP clients register dynamically and require an explicit consent screen.
Database policies limit those clients to reading the signed-in person's notes and agenda.
The registered desktop client and first-party web sessions can edit their own library.

Google Calendar is a separate, optional read-only connection. Its refresh tokens are
encrypted on the server, inaccessible to normal database clients and MCP tools. Recording
does not depend on Google, Supabase or Vercel being available.

## Synchronization contract

Completed sessions sync as a versioned document: manifest, transcript, timestamped bullets
and current Markdown. A server transaction compares the expected version before writing
and retains previous documents. Repeating an identical write is safe. The Mac maintains
a per-account sync index on disk and compares content hashes; it can upload changes after
a restart or an outage without needing a running in-memory queue.

When both copies changed, Voice Notes preserves the local document as a separate conflict copy
before accepting the cloud document. An editor draft is private recovery state and is never
uploaded. Local removal is not a cloud deletion: deletion must be explicit in the cloud
library. This prevents an offline or disconnected Mac from silently deleting shared data.

Each note syncs independently. A rejected document remains local and appears under
Connections → Notes waiting to sync; it does not block other notes or the calendar.
An upload rejected because another device saved first fetches the latest document and
preserves both versions in the same pass. Edits made while an upload is in flight remain
eligible for the next pass. Sign-out invalidates pending responses, including manual sync
tasks. Cached agenda data is bound to the same account as the local library.

## Development

`cd web && npm ci && npm run dev`. Copy `.env.example` to `.env.local` and populate it
with the new Murmur project's values. `npm run check`, `npm test` and `npm run build`
verify the web application. Database migrations live in `supabase/migrations/`.

`npm run test:integration` requires Docker and the Supabase CLI. It starts a separate
local `murmur` stack on ports 5632x, applies the migrations, runs the rollback SQL access
fixture and five tests using real OAuth tokens. Fixtures are synthetic and removed by the
tests. The runner leaves this stack available for development; `supabase stop` from the
repository root stops only this project's stack. Local signing keys are generated into an
ignored file and are never deployment credentials.

Version conflicts use PostgreSQL error `PT409`, which PostgREST returns as HTTP 409 without
transaction retry. Avoid `40001` for this logical condition: it denotes a serialization
failure and can cause automatic retries instead of a prompt conflict response.

Production needs a stable site URL in Vercel, Supabase's allowed redirects and the MCP
resource audience. Google OAuth needs a Web application OAuth client with the Supabase
Auth callback and Voice Notes Calendar callback registered in Google Cloud.
