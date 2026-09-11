# Voice Notes deployment

## Created

- Vercel project: `murmur`, team `jason-zanes-projects`.
- Site: https://murmur-rho-pied.vercel.app
- Latest verified deployment: `dpl_7TpugBwNJhA7QRVaaeWzhicHVX2c`, READY on 9 September
  2026, including shared Account settings, the phone layout correction and updated connection instructions.
- Remote MCP: https://murmur-rho-pied.vercel.app/mcp
- New Supabase organization: **Murmur**, `dxqglhelvchutaqnjiyi`.
- Supabase project: **Murmur**, `olxjfdsslbpdvywsnzrc`, Sydney (`ap-southeast-2`).
- Approved project cost: **$0/month** on Free. No paid plan was enabled.
- All four checked-in migrations have been applied. All six public tables have RLS.
- The Auth service has an ES256 signing key.

## Completed Auth configuration

Supabase OAuth Server and dynamic client registration are enabled, with authorization
path `/oauth/consent`. The Site URL is the stable Vercel origin,
and the two redirects are its `/auth/callback` and `murmur://oauth/callback`.
The `public.murmur_access_token_hook` hook is enabled. The dedicated
`voice_notes_server` secret and public **Voice Notes for Mac** client are configured
privately and deployed; the native client is allowed in `first_party_clients`.

The setup helper handles both production OAuth-client response formats and pagination;
four focused tests pass. The global Supabase CLI belongs to another account and must not
be used for this project.

## Google configuration and live check

Google project `voice-notes-508106` now has the Voice Notes external consent app, owner
test user and homepage/privacy/domain branding. Google's API Services User Data Policy
was accepted with the user's explicit approval. The **Voice Notes Web** OAuth client is
created, its credentials are stored privately and deployed, and Google's provider is
enabled in Supabase. The authorized origin is the stable Vercel origin. Redirects are:

- `https://olxjfdsslbpdvywsnzrc.supabase.co/auth/v1/callback`
- `https://murmur-rho-pied.vercel.app/api/google/callback`

Google Calendar API is **Enabled**. The user separately approved its API terms and
activation completed. Data access was saved with `openid`, userinfo email/profile and
`calendar.events.readonly`; no Calendar write scope is requested.
`NEXT_PUBLIC_GOOGLE_ENABLED=true` is deployed. Actual Google sign-in completed using
`jasonzanehunt@gmail.com`, and the authenticated private library loaded successfully.

## Booking links and multiple calendars: built, not deployed

Built and tested locally on 11 September 2026. Nothing below has been applied to
production; each step needs the owner's approval.

1. Apply `supabase/migrations/20260911090000_murmur_scheduling.sql`. The existing Google
   connection becomes the first account with its read-only scope. Cached agenda events are
   cleared and rebuild on the next refresh.
2. In Google Cloud → Data access for `voice-notes-508106`, add
   `calendar.calendarlist.readonly`, `calendar.events` and `calendar.freebusy`. They are
   sensitive scopes: until Google verifies the app, only test users can grant them and
   Google shows its unverified-app screen. Verification needs the privacy policy (updated
   for booking links) and a short demo of the consent and booking flow.
3. Deploy the web app. No new environment variables are needed;
   `GOOGLE_TOKEN_ENCRYPTION_KEY` also derives the booking rate-limit key.
4. As the owner: Connections → Show my other calendars (grants the calendar list), tick
   calendars, then Booking links → Allow booking, choose a link name, hours and calendar,
   and add a meeting type.
5. Install a Mac build from this branch so booked meetings carry their guest answers and
   template. Busy times from the Mac are shared only after turning on Settings → Meetings →
   Keep booking links clear of events on this Mac.

Live checks still to do after deployment: a real booking creates the event and Meet link
and Google emails the guest; reschedule and cancel from the guest's link update the event;
the Mac names the booked meeting and applies its template.

## Acceptance and live checks

The user accepted this delivery as complete on 9 September 2026, with the final two-person
Google Meet check deferred. Google Calendar consent completed;
Refresh returned three upcoming events. Native sign-in and sync also succeeded after
repairing the authentication callback crash described below.

A private, five-minute test event for 18:35 Sydney on 9 September opened automatically
in Chrome at 18:34:04. Its preview exposed a premature-recording bug, now repaired in the
installed build; the preview stayed idle afterward. A joined call with another participant
has not been verified after that fix and is the accepted deferred check.

Google Audience now visibly reports **In production**. Full public Google verification is separate.
The production remote MCP is connected to the owner's Claude account through dynamic client
registration and the normal OAuth consent flow. Claude discovered all six read-only tools and
used Search and Fetch to retrieve the exact three-line sync test note, including its web edit.
The connected Claude and native app grants are visible in Voice Notes Connections.
Claude's List upcoming meetings tool also returned the private test event and its correct
18:35–18:40 Sydney time. The test Meet tab is closed and the temporary Calendar event was removed.
The full Mac → production → web → Mac round trip passed with the labelled sync note.
A further edit saved while signed out on the Mac arrived on the web after reconnection.
The Mac is signed back in and synced; the network connection was not disabled during this check.

Public production MCP checks pass: an unauthenticated initialization returns 401 with
the correct resource challenge; protected-resource and authorization-server discovery
return 200, with S256 PKCE and dynamic registration advertised. The actual authenticated
Claude connection and note retrieval also passed.

The encryption key is generated locally and configured in Vercel. The environment helper
uploads only app variables and never the Supabase management token. Local secret files are
ignored by Git and have mode 0600.

## Current verification

- Native `make test`: 55 cases across 11 suites, including conflict recovery, filesystem
  import, interrupted synchronization and source-checked action metadata. Optional
  hardware/model smoke tests are skipped unless enabled. The latest model-enabled run
  passed both strengthened short/long Apple Intelligence tests in 22 seconds; the latest
  full native run also passed real microphone and Apple/Parakeet speech checks.
- Version 0.4.0 is installed at `/Applications/Murmur.app`, signed with the stable Apple
  Development identity. The installed stdio MCP smoke test passed. The app is running with
  the real library. The user confirmed two consecutive dictations
  insert text and return to idle after the AirPods/cancellation repair. See
  `DICTATION-VERIFICATION.md`.
- The installed build now lets other notes and the calendar continue when one note fails
  to sync. It recovers upload races immediately, retains edits made during requests, and
  discards late responses after sign-out. Seven isolated native workflow tests cover this.
- Local summary actions and unresolved questions are extracted from source passages and
  retained outside the final prose rewrite. Tests reject invented task words, names from
  other passages and deadlines from a different sentence. The real model checks preserve
  Maya's Thursday checklist, Sam's Monday worksheet and unresolved support ownership.
  These fixture checks do not guarantee every generated summary is accurate.
- Web TypeScript check, 13 existing tests, four OAuth-setup tests and production build passed.
- Five additional integration tests passed against isolated local Supabase Auth and
  PostgREST. They cover real PKCE consent and ES256 tokens, native/MCP audience separation,
  token refresh, account isolation, denied MCP writes, signed-token validation, idempotent
  uploads and version conflicts. No production account was used for these fixtures.
- Integration checks caught and fixed missing explicit server-role permissions and a
  conflict error code that PostgREST retried. Logical version conflicts now return HTTP 409
  immediately and preserve the competing document and previous revisions.
- Local browser checks passed for sign-in, OAuth consent/revocation, draft recovery after
  reload, and preserving source corrections while resolving a note conflict. The library,
  Connections and consent screens were inspected at desktop/mobile sizes. Date formatting
  now happens in the browser to avoid locale-dependent hydration errors.
- Vercel reports the production deployment READY and live Google sign-in passed. Calendar
  consent and refresh pass, and native account sign-in and synchronization pass. Mac → production
  → web → Mac passed with a labelled note. Claude's authenticated remote Search and Fetch
  returned the exact saved note. The phone Account layout was visually checked at 390 × 844,
  corrected so its action link does not squeeze the description, deployed and checked again.
- Supabase security advisor has one informational notice for the intentionally server-only
  `calendar_credentials` table: RLS is enabled with no client policy, and table access is
  revoked from authenticated/anonymous clients. [Advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
- Performance advisor notes the new indexes have not been used yet. This is expected in an
  empty project. [Advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

## Naming

**Voice Notes** is the working display name. Earlier name concepts are parked and final
branding is deferred, as recorded in [the identity notes](IDENTITY.md). Infrastructure
names, the hosted origin, URL scheme and native storage/signing identity remain stable.
A future public-origin change must update redirects and the MCP audience together while
preserving native signing, stored credentials and existing notes.

The public [working-name page](https://murmur-rho-pied.vercel.app/identity.html) requires
no app sign-in and links to the app. It no longer presents alternative names.

The requirement-by-requirement [completion audit](VERIFICATION.md) records the verification
results, coverage limits and accepted Meet-test deferral. The delivery is complete with
that deferral; unperformed checks are not recorded as passed.

## Dictation bar update

Settings → Dictation offers **Show live text**, **Top / Bottom / Left / Right**, and a
recording-free Preview. The capsule has no shadow and sits eight points from the usable
screen edge, clear of the menu bar and visible Dock. All four positions and compact/
expanded previews were checked visually. Preferences survived a relaunch; the current
choice is Bottom with live text off. Five dictation lifecycle regression tests passed
after the bar changes, and the stable signed build is installed and running.

## Account settings and browser callback repair

Settings → Account is available in the installed Mac app and at `/settings` on the web.
Both show the signed-in email, Google Calendar account, connection controls and privacy
information. The Mac sidebar also shows account identity. Connections reuses the same
account presentation. Native settings retain the Dictation, Meetings and General tabs.
The web sign-out action affects only the current browser session. Calendar refresh now
updates its displayed timestamp immediately.

The supplied 17:47 crash report and earlier local reports identify the browser completion
closure in `CloudAccount.signIn()`: Swift 6 inferred MainActor isolation, while
AuthenticationServices invoked it on an XPC queue. The completion is now explicitly
nonisolated and Sendable and resumes the continuation safely. Real sign-in then succeeded.
A rejected cloud session now offers Sign in again directly in Account settings; live
reconnection returned to Synced. Ten focused native authentication/sync tests passed,
along with the web's 17 tests, TypeScript check and production build. Stable signing was
preserved and the installed bundle passed strict signature verification. Native Account
and the production web Account page were visually checked at desktop size.
