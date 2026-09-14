# Voice Notes cloud

The macOS app remains the recording and dictation engine. Its plain-file library works
offline. The hosted Next.js companion on Vercel stores an account-owned copy in Supabase,
provides Google authentication, calendars and booking links, and exposes a read-only remote
MCP URL.

## Trust and authentication

Web sign-in uses Supabase Auth and PKCE. The native app uses the same OAuth 2.1 server,
with a registered public desktop client, a custom-scheme callback, PKCE S256 and state.
Its refresh token lives in the macOS Keychain. No service key ships with the Mac app.
Third-party MCP clients register dynamically and require an explicit consent screen.
Database policies limit those clients to reading the signed-in person's notes and agenda.
The registered desktop client and first-party web sessions can edit their own library.

Google Calendar is a separate, optional connection. A person can connect several Google
accounts and choose which of their calendars count. Connecting asks only to read events and
the calendar list. Turning on booking links asks that account for `calendar.events` and
`calendar.freebusy` through incremental consent. Refresh tokens are encrypted on the server,
inaccessible to normal database clients and MCP tools. Recording does not depend on Google,
Supabase or Vercel being available.

## Booking links

Booking follows the Calendly and Cal.com model, with Google providing calendar invitations, video links and optional email delivery.
Each person has one public page, `/book/<handle>`, and a page per meeting type,
`/book/<handle>/<slug>`. Open times come from their weekly hours and date changes, minus
busy time on every ticked calendar (Google free/busy), busy times shared from the Mac
(start and end only, opt-in) and existing bookings. The slot engine is adapted from
Cal.diy (MIT; see `web/src/lib/scheduling/LICENSE-cal.diy`).

A booking holds its time with a pending row. A PostgreSQL exclusion constraint makes it
impossible for two live bookings of one person to overlap, however requests race. The
server then creates the event on the host's chosen calendar with `sendUpdates=all`, so
Google sends the invitation from the host's own account, and requests a Meet link when the
meeting type uses Meet. If Google refuses, the pending row is removed and nothing is booked;
a pending row older than ten minutes is released. Guests receive a private link whose
token sits after `#` and is stored only as a SHA-256 hash. It lets them reschedule or
cancel, and Google announces either change. Public endpoints require Voice Notes' own
origin and are rate limited per keyed hash of the address. Guests never read or write the
database directly.

When the Mac records a booked meeting, the session keeps the guest's answers, labelled as
written before the meeting, and its notes use the meeting type's template. Connected AI
apps can list booking links and bookings and suggest free times; they cannot book, move or
cancel anything.

## Shared meeting workspace

Mac and web use Home, Calendar, Notes, Dictation and Booking links, with Connections and
Settings below. Mac keeps capture, dictation and device permissions native. Booking and
connected-account management use the same hosted screens inside an isolated WKWebView.
A bearer-only `/api/native/session` exchange creates a separate web session without sending
an email or exposing the Mac refresh token to JavaScript. External consent opens the browser.
The common navigation, accent and typography tokens are in `shared/design/tokens.json`;
run `python3 Tools/generate-design-tokens.py` after changing them.

Calendar supports agenda, day and week views, source filtering, meeting details and linked
notes. Preparing a note creates a private note containing the booking context; it does not
start recording or change the calendar event. Dictation and audio capture require the Mac.

## Availability and meeting messages

Every meeting type can inherit default availability, reference a named availability profile,
or define custom weekly hours, time zone and date exceptions. Named profile edits affect
future availability for all linked types; existing bookings retain their times. Duration,
location, notes template, guest questions, notice, buffers and booking limits belong to the
type. Destination calendar and email sender can override the account defaults. Connected
busy calendars remain an account-wide protection against double booking.

Optional Gmail `gmail.send` consent permits sending only, with no inbox-reading scope.
The Gmail API must be enabled on the Google project. Connections controls the default
sender and master sending switch. Each meeting type has preparation, reminder and thank-you
recipes, all disabled by default. Thank-you messages require the host to mark attendance
completed. Recipes use an allowlisted set of variables and plain-text email.

Vercel invokes `/api/messages/dispatch` every minute in production; it requires a random
`CRON_SECRET` production environment variable. This schedule needs a Vercel plan supporting
minute-level cron. Cron timing and delivery are best effort. Messages have a unique schedule
key per recipe, booking and start time. Sends and booking changes share a per-booking lease.
Cancelled, moved or expired messages are suppressed before sending. Ambiguous Google
responses are marked `needs_attention` and never automatically retried; check Sent mail.
The history reports Google acceptance, not proof of delivery. Sending is capped at 100
attempts per account per day, with manual requests additionally capped at 30 per hour.

When enabled in Connections, completed booked notes produce private follow-up drafts from
explicitly labelled Decisions, Actions or Next steps sections. Transcripts, guest answers
and unrelated note sections are excluded. The host reviews and edits each draft, then
explicitly sends it. This is section extraction, not a second AI summarisation step.

Apply `20260911100000_meeting_workspace_messages.sql` and
`20260911110000_reusable_availability.sql` before deploying this workspace. Hosted migrations
are applied individually after checking the target project, not with `supabase db push`.
All new tables use owner-scoped RLS; email mutations require first-party editor sessions.
Remote MCP remains read-only and cannot send email.

## Synchronisation contract

Completed sessions sync as a versioned document: manifest, transcript, timestamped bullets
and current Markdown. A server transaction compares the expected version before writing
and retains previous documents. Repeating an identical write is safe. The Mac maintains
a per-account sync index on disk and compares content hashes; it can upload changes after
a restart or an outage without needing a running in-memory queue.

When both copies changed, Voice Notes preserves the local document as a separate conflict copy
before accepting the cloud document. An editor draft is private recovery state and is never
uploaded. Local removal is not a cloud deletion: deletion must be explicit in the cloud
library. This prevents an offline or disconnected Mac from silently deleting shared data.

Each note syncs independently. A rejected document remains local and is listed under
Settings ▸ Connections on the Mac; it does not block other notes or the calendar.
An upload rejected because another device saved first fetches the latest document and
preserves both versions in the same pass. Edits made while an upload is in flight remain
eligible for the next pass. Sign-out invalidates pending responses, including manual sync
tasks. Cached agenda data is bound to the same account as the local library.

How to run and test the web app is in [DEVELOPMENT.md](DEVELOPMENT.md); how to deploy your own copy is in [SELF-HOSTING.md](SELF-HOSTING.md).
