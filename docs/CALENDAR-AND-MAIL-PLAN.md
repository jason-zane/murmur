# Calendar and Mail: review and implementation plan

Prepared 30 September 2026 against baseline checkout `492af1a`.

## Implementation status — 30 September 2026

The review below describes the baseline. The working tree now implements calendar-history repair, namespaced event identity, multiple Google accounts and independent calendar visibility/availability/suggestions, cached date-range loading with durable paginated jobs, verified push channels with renewal and missed-notification reconciliation, native and web week grids, event creation/editing/removal, time zones, reminders and web RSVP. EventKit edits resolve the original occurrence and check its last-modified date; Google edits use ETags. Date-only all-day bounds survive changes in the viewer’s timezone.

Mail now has a Gmail connection flow, a unified web mailbox with folders, search, labels, bulk actions, attachments, drafts, reply/reply-all/forward, scheduled sending and Undo. The native mailbox provides downloaded conversations, account/folder navigation, attachments, local and Gmail drafts, compose/reply/forward, per-account signatures and an offline send queue. Provider-rich drafts retain HTML, inline attachments and revision checks on both clients; the native composer offers an explicit plain-text conversion for body edits. Native advanced workflows open the hosted mailbox. No mailbox data is added to third-party MCP privileges.

Delivery uses an encrypted server outbox and conditional claims. Uncertain results are reconciled with Sent using the operation’s deterministic message ID and are never automatically resent. Local Undo persists its intent; server cancellation reserves the operation before delayed queue requests arrive. Partial calendar pagination retains checkpoints and never replaces complete coverage until the job commits.

**Scope update, 30 September:** Outlook is explicitly deferred. The workspace now uses Today, Calendar, Mail and Notes, with contextual booking/dictation tools, a guided Connected apps hub and optional first-run setup. Calendar/Gmail connection status is separated by actual provider grants.

**Longer-term roadmap, beyond the implemented release:** incremental provider cursors and mailbox-wide offline import/search, rich editing, snooze/notifications and complete recurrence-series controls, capability-specific disconnect/cache purging, Microsoft Graph adapters (deferred) and live account acceptance tests.

The signed Mac app is installed and the four migrations and matching hosted backend were deployed on 30 September. Scheduled workers report HTTP 200; live historical calendar downloads and the Mac-to-browser Google handoff have been verified. Connecting Gmail still requires Google mailbox consent. Live Gmail delivery and other provider mutation acceptance remain outstanding. Validation details are in `docs/CALENDAR-AND-MAIL-VALIDATION.md`.


**Recommendation:** make Calendar trustworthy first, then introduce a complete Gmail mailbox on a shared account and synchronisation foundation. Preserve native recording and dictation. Design the provider boundary for Microsoft now, and deliver Outlook after Gmail passes the same reliability tests.

The baseline review below is supported by provider documentation and open-source research. Implementation and synthetic native/browser visual checks subsequently completed as described above. The particular missing meeting has not been diagnosed against a live provider account.

## 1. What exists, and why past meetings disappear

The current product has a meeting agenda, several calendar layouts, Google account connections, booking links and booking-related outgoing email. It does not yet have the data model or editing workflows of a complete calendar or mailbox.

| Finding | Evidence in this checkout | Consequence and priority |
| --- | --- | --- |
| Mac requests upcoming events only | `Sources/Murmur/Cloud/CloudSync.swift:229` requests `api/calendar`; `web/src/app/api/calendar/route.ts` enables history only when `workspace` is present | **P0:** completed Google meetings are absent from the response used by the Mac |
| Mac independently discards past events | `CloudSync.swift:401`, `applyAgenda`: `agenda.events.filter { $0.ends_at > Date() }` | **P0:** even requesting history will not fix the problem alone; restoring the disk cache also applies this filter |
| Web history has a fixed horizon | `web/src/lib/calendar.ts`, `refreshConnection` and `agenda`: approximately 90 days before and after now for the workspace | **P1:** navigating outside the fetched window looks like an empty calendar; changing dates does not fetch that date range |
| Results can be silently incomplete | `calendar.ts`: 750 database rows before deduplication; 250 results for the ordinary agenda; first 25 selected calendars; first 200 sources | **P1:** busy accounts can lose visible events; history can consume the result cap before future events are reached |
| Display inherits meeting-detection filters | `CalendarService.events(from:to:)` excludes all-day, free-time and declined local events; `normalizeEvent` excludes all-day and declined Google events | **P1:** holidays, birthdays, free blocks and declined invitations cannot be represented faithfully. Google timed free events are not filtered consistently with local events |
| Multiple Google accounts already exist | `saveConnection`, `calendar_connections`, `calendar_sources`, Connections UI with “Add another Google account” | Build on this. Newly discovered non-primary calendars default to unselected; older grants may expose only `primary` until reconnected |
| Mac reduces account information to one legacy summary | `CloudSync.CalendarPage` decodes `connection`, not full `connections` and `calendars`; `CloudMeeting` omits their IDs | Mac cannot explain which source is missing, offer source selection, or reliably distinguish identical provider IDs across accounts |
| Identity is lost above the database | DB key is `(connection_id, calendar_id, id)`; client uses `google-` plus event ID; notes link by that string | **P1:** collisions and ambiguous note links become more likely as accounts are added |
| Deduplication can erase useful source context | Server merges by iCal UID/start, or bare ID; Mac uses matching title or conference URL within one minute | Independent events can be merged. Copies of a real invitation need source provenance so filtering and editing target the correct calendar |
| Display selection also controls booking availability | `calendar_sources.selected` and Connections copy | Hiding a calendar should not accidentally make its busy time bookable |
| Updates depend on fetches, with weak freshness UX | Server refresh is request-driven and five-minute throttled; web workspace loads at mount/manual refresh | Leaving a web calendar open does not itself keep it current. The Mac’s view timer only rereads its current cache |
| One bad source can prevent an account snapshot updating | `refreshConnection` fetches selected sources sequentially before `replace_calendar_events` | Other accounts are isolated, which is good; calendars within one account are not. Large accounts also risk the route’s 60-second limit |
| Some display grouping uses start-day equality | `CalendarWorkspace.dayColumn`, month cells | An event spanning midnight is not shown on every day it overlaps |
| Email is send-only, tied to bookings | `web/src/lib/messages/service.ts`, `/api/messages`, `EmailConnection` | No received messages, threads, mailbox labels, general composer, inbox search or attachment store. Existing send failure handling is worth preserving |

**Most direct explanation of the reported symptom:** a completed Google event cannot reach the Mac calendar through the current cloud path because it is removed twice. EventKit can still supply a local copy, so the symptom depends on which calendars are available on this Mac. This is a confirmed code defect, not proof that it is the sole cause of the particular missing meeting.

For a missing event in the web calendar, investigate source selection, failed refresh, horizon and truncation instead; the web already requests `workspace=1`. The refresh function’s “next 30 days” comment is stale: its implementation fetches ±90 days.

### Immediate repair, before the larger redesign

1. Add yesterday’s event to the Swift workflow fixture and assert it survives sync, restart and offline cache restoration. Include an upcoming event so reminder behaviour can be checked separately.
2. Request the existing history-capable endpoint from the Mac and retain completed events in the calendar cache. Keep near-now filtering inside meeting detection and reminders. Do not let a history fix trigger past meeting offers.
3. Display the current history limit and incomplete/error states until range retrieval replaces the legacy endpoint. Merely changing to `workspace=1` still leaves the 750-row cap and fixed window.
4. Test the real missing day against the provider with the user’s existing connection during implementation, recording counts and source IDs rather than copying private meeting content into logs.

Use `make test TEST_ARGS='--filter CloudSyncWorkflowTests'` for the focused Mac regression, then the relevant meeting schedule tests. The fixture currently matches the literal `api/calendar` path and must be updated alongside the request. Do not treat a passing old fixture as coverage of history.

## 2. Product direction

Make **Calendar, Mail and Notes** distinct workspaces with useful links between them. Home answers “What needs my attention today?” Recording and dictation retain their existing native controls. Booking links remain a scheduling tool within the product.

Plan for Mac and web. Keep Calendar native on Mac, with shared domain contracts and provider services. Build the hosted mailbox first, using the existing isolated `CloudWorkspace` for an early Mac preview; a native Mac mailbox with offline drafts and keyboard behaviour is a separate release gate before claiming a first-class Mac experience.

### Calendar experience

| Area | Required experience |
| --- | --- |
| Account/source rail | Work and personal accounts, calendars grouped beneath them, visible selection, read-only status, last successful update, actionable connection errors |
| Main canvas | Agenda, Day, real time-grid Week, Month; persistent view/date; Today; jump to date; keyboard navigation; sensible first-day-of-week preference |
| Events | All-day strip, overlapping appointments, multi-day spans, recurring instances, cancelled/declined states, time zones, location, description and attachments/links |
| Details | Source account/calendar, organiser, attendees and responses, Join meeting, Prepare/Open note, edit/RSVP when allowed |
| Editing | Create, edit, reschedule, cancel/delete, invite guests, choose destination calendar, reminders, recurrence scope and conference details |
| Search | Date, title, people, location and description; explicit account scope; search beyond the currently visible week |
| Reliability | Cached view immediately; loading history distinct from empty; partial failure identifies the affected source; “Try again” at the failed connection |
| Meeting context | One note link per event occurrence, source email thread when linked, relevant previous notes, recording state where appropriate |

Do not turn “Week” into seven narrow lists: time position, duration, conflicts and free time must be visible. Opening a previous day should feel as normal as opening tomorrow.

Calendar actions must respect ownership. Attendee actions are RSVP or removing one’s own copy; organiser cancellation can notify everyone. Explain this in the action flow. A moved recurring event must retain its note association. Support “this occurrence” and “entire series” first; gate “this and following” until provider-specific series splitting is implemented and tested.

Separate three settings per source: **Show in Calendar**, **Use for booking availability**, and **Use for meeting suggestions**. A hidden work calendar can still prevent double booking. Choose a default write calendar separately, with an explicit destination on every event creation flow.

Follow existing DS tokens, Australian English and component vocabulary. Indigo remains the interaction accent. Preserve provider colours as data but map visible calendar markers to an accessible, non-red palette; red remains exclusive to recording. Account names and icons must distinguish sources without colour alone. Keyboard and VoiceOver testing are required for the calendar grid, popovers and drag alternatives.

### Mail experience

The useful first release is a daily mailbox, not a preview of recent messages.

| Area | Required for Gmail daily use |
| --- | --- |
| Navigation | All inboxes, account inboxes, Starred, Sent, Drafts, Archive/All Mail, Spam, Bin and custom labels; visible account identity |
| Reading | Fast thread list, conversation reader, quoted-text folding, unread/starred state, safe HTML/plain text, attachment preview/download |
| Triage | Archive, read/unread, star, labels, move to Bin, report spam and undo where still possible; bulk actions with per-item failure reporting |
| Compose | New message, Reply, Reply all, Forward, To/Cc/Bcc, rich/plain text, attachments, signatures, persistent autosaved drafts and clear sender |
| Sending | Outbox, delayed dispatch for Undo send, progress/failure state, prevention of duplicate sends, correct conversation threading |
| Search | People, subject, text, dates, labels, unread, attachments; pagination through older results; cached-only scope identified offline |
| Accounts | Multiple Gmail accounts, separate signatures and drafts, reconnect one without disrupting others, per-account notification preferences |
| Productivity | Keyboard shortcuts, snooze, scheduled send, create/link a note, create an event from a message, reviewable meeting follow-up drafts |

Snooze and scheduled send should initially be explicitly Concourse features; do not imply they map to Gmail’s native scheduled/snoozed state. They require a durable server job even when the Mac is asleep. Provider drafts should round-trip so a message can be continued in Gmail; local unsynchronised edits need conflict handling if it is also edited there.

Default replies to the receiving account, not the last globally used sender. Start with the verified primary address; add aliases only after querying and enforcing provider-authorised send-as identities. Autocomplete can begin with recent correspondents and manual entry; address-book integration is a later capability with separate consent.

Mail-to-calendar extraction produces an editable draft with explicit time zone, date and recipients. Preparing a follow-up must not send it. Email content is untrusted input and cannot authorise an AI action. Do not automatically expose mailbox content through the current notes/agenda MCP grants.

## 3. Open-source research and reuse decisions

These are primary-source product and architecture references, not executed security or performance evaluations. No third-party application was installed or benchmarked. Pin and review exact revisions and dependency licences before importing code.

| Reference | What to learn or reuse | Fit and decision |
| --- | --- | --- |
| [Zero / Mail0](https://github.com/Mail-0/Zero) | Unified provider experience, React/TypeScript mailbox composition, account-oriented sync | Closest web-stack reference; MIT at the reviewed repository. Its README describes additional infrastructure including Durable Objects/R2. Evaluate small components and provider boundaries, not a wholesale application fork |
| [Mailspring](https://raw.githubusercontent.com/Foundry376/Mailspring/master/README.md) | Unified inbox, composer, keyboard workflow, local cache and separate sync engine | Electron/React with local C/C++ sync; GPLv3. Strong desktop behaviour/architecture reference, but a large mismatch for a SwiftUI client and existing hosted backend |
| [Thunderbird](https://www.thunderbird.net/en-US/features/) | Account organisation and the completeness expected from an established personal mail/calendar client | Use as an acceptance benchmark for everyday workflows; not an embeddable component recommendation |
| [Roundcube](https://raw.githubusercontent.com/roundcube/roundcubemail/master/README.md) | MIME handling, folder/search workflows and mature webmail coverage | PHP/IMAP stack; GPLv3-or-later with stated plugin/skin exceptions. Useful reference, poor fit as the foundation of this app |
| [Nextcloud Calendar](https://github.com/nextcloud/calendar) | Calendar/source organisation, event editing, attendees, free/busy and contextual integrations | AGPL-3.0 application tied to Nextcloud. Product reference rather than a replacement backend |
| [FullCalendar](https://fullcalendar.io/license) | Evaluate a mature web calendar grid before building one from scratch | Standard is MIT; Premium has separate terms. Prototype Standard for web Day/Week/Month; retain native SwiftUI implementation on Mac |

**Build/reuse decision:** own the provider contracts, identities, sync state, operation queue and links to notes. Reuse maintained, reviewed libraries for MIME parsing/composition, HTML sanitisation and web calendar layout. Evaluate their actual maintenance and fixtures in the implementation spike. Do not import an entire second auth/database/AI stack simply to obtain an inbox UI.

A short spike should exercise a candidate mail renderer against multipart messages, malformed HTML, inline CID images, Unicode headers, quoted replies and large attachments. A calendar grid spike should prove keyboard access, overlapping events, all-day rows and DS styling. Reject a library that cannot meet those behaviours without substantial forks.

## 4. Accounts and domain model

### Shared account foundation

Evolve calendar-named connections into provider accounts with independently enabled Calendar and Mail capabilities. A person may connect Mail without Calendar, or Calendar without Mail. Connecting a second Google account must never sign the person out of their Concourse account.

Use a stable, verified provider subject and issuer/tenant context for identity; an email address is a display field, not the permanent key. The current callback matches on email and can fall back to null when userinfo fails. Fail safely when identity cannot be established; reconnect must update the intended account without merging unknown identities.

OAuth remains PKCE/state based, incremental by capability. Persist granted scopes, not just requested scopes. Scope upgrades must preserve existing capabilities and any still-valid refresh token when the provider does not issue a new one. Store rotating refresh tokens atomically, with per-account concurrency control. Surface revoked access, temporary rate limits and tenant policy blocks as different states.

| Proposed entity | Purpose and key properties |
| --- | --- |
| `provider_accounts` | Owner, provider, stable provider identity, display address, capability/grant state |
| Private credentials | Encrypted refresh token, encryption-key version, rotation metadata; never returned to clients |
| `calendar_sources` | Account/source identity, name, time zone, permissions, independent display/availability/suggestion preferences |
| Calendar records and occurrences | Namespaced provider ID, series ID, original occurrence start, current times, date-only bounds, status, organiser, attendees, version and source provenance |
| `calendar_coverage` | Which range is completely fetched for each source, pending ranges, successful timestamp and errors |
| `sync_checkpoints` | Provider cursor, query scope/window, staged page progress, subscription expiry and recovery state |
| Mail messages/threads | Account-scoped provider IDs, headers, sender/recipients, body references, labels/folder, timestamps and versions |
| Drafts and attachments | Account ownership, provider draft ID, revision, local edits, safe metadata and private object reference |
| `outbound_operations` | Idempotency key, intended action, expected version, queued/running/confirmed/failed/uncertain state, provider result |
| `context_links` | Explicit links between notes, event occurrences and mail threads, retaining owner/account boundaries |

Keep Gmail labels and Outlook folders/categories as provider-specific concepts behind common operations. Do not force a Gmail message with several labels into one artificial folder. Do not merge conversations between accounts solely by subject.

Event identity must be source-qualified. Recurring instance identity uses the provider’s original occurrence key, not its current start time; rescheduling changes presentation, not the note link. Deduplication is a presentation group retaining all backing copies and permissions. If EventKit cannot reliably prove equivalence to a provider copy, show both or support an explicit source preference instead of dropping one based on title alone.

### Migration without breaking installed copies

1. Add new structures and stable IDs alongside current tables. Preserve existing connection UUIDs or an explicit mapping because bookings and mail settings reference them.
2. Backfill known event/source identities and mark unknown provenance for reconciliation. Link legacy `google-<id>` notes only when a unique match exists; preserve unresolved legacy links rather than guessing.
3. Keep `/api/calendar` and its legacy `connection` shape working for older Mac builds. Introduce a versioned range endpoint and shared response fixtures for new clients.
4. Move provider sync out of the note-sync pass into an independent coordinator/store. Existing note `CloudSync.state` and its behaviour remain intact; Calendar and Mail receive their own domain state.
5. Move the existing booking sender onto the common delivery service through an adapter. Preserve scheduled-message IDs, disabled defaults and uncertain-send handling. Enabling Mail must not enable booking automation.
6. Roll out new reads first, compare counts/identities, then enable mutations by capability. Keep feature flags and a rollback path that retains new data. Do not delete old structures until supported clients have migrated.

## 5. Calendar retrieval and updates

### A range contract instead of one finite agenda array

Proposed endpoint: `GET /api/calendar/events?from=<instant>&to=<instant>&cursor=<opaque>` with authorised source selection. It returns events, `nextCursor`, coverage and per-source freshness/errors. Bound individual requests, for example to a month or quarter, but permit navigation to any date the provider can supply by requesting additional ranges.

The overlap predicate is `event.end > from && event.start < to`. All-day events retain start and exclusive end **dates**, interpreted in their calendar’s time zone, rather than becoming arbitrary UTC-midnight timestamps. Display overlaps on every relevant day. Test Sydney and another daylight-saving zone, including spring-forward/fall-back and travel between time zones.

Cache a useful initial range, proposed as the previous 12 months and next 12 months, with the visible period fetched first. This is a performance default, not a browsing limit. Fetch older ranges on demand, preserve completed cached ranges, and disclose when offline data is unavailable. Global search can fetch provider results outside that cache.

Freshness is per source. Never claim “No events” until all selected sources have complete coverage or clearly identify the missing ones. Pagination must not mark a range complete before the final page succeeds. An account with 40 selected calendars must either sync them all or explicitly report a supported limit; silent slicing is unacceptable.

### Durable synchronisation

Google supports incremental collection sync with sync tokens; invalid tokens require resynchronisation. Its event-list API restricts combinations such as a sync token with `timeMin`/`timeMax`/`orderBy`. Build provider collection synchronisation separately from bounded historical queries; do not attach a token to the current rolling-window request. Process cancellations and recurrence exceptions. Stage recovery before replacing the usable cache. [Google sync guide](https://developers.google.com/workspace/calendar/api/guides/sync), [event-list contract](https://developers.google.com/calendar/api/v3/reference/events/list?hl=en).

Use Calendar watch notifications to enqueue retrieval; notifications are signals, not event bodies. Renew channels before expiry, validate channel identifiers/tokens, and reconcile periodically because notification delivery is not sufficient by itself. EventKit should react to store-change notifications and app activation. [Google Calendar push guide](https://developers.google.com/workspace/calendar/api/guides/push).

Run work in resumable jobs with a lock/lease per source, bounded batches, retry/backoff and a dead-letter/recovery path. Do not run a complete account import inside a page GET. Store page progress and advance the committed checkpoint only after the corresponding data is committed. Handle duplicate notifications and overlapping scheduled jobs idempotently.

Google remains the authority for connected events; EventKit remains the authority for calendars available only on this Mac. Do not upload local calendar titles or descriptions simply because busy-time sharing is enabled. Cross-device access to local-only calendars would be a separate opt-in feature.

## 6. Gmail implementation

### Consent and rollout gate

The current `gmail.send` grant cannot read a mailbox. A read-only pilot needs `gmail.readonly`; a daily-use mailbox generally needs `gmail.modify`, which covers reading, composing, sending and normal mailbox changes but not bypassing Bin for immediate permanent deletion. Do not request `mail.google.com` for the initial product. Keep send-only booking users on their existing grant. [Gmail scope reference](https://developers.google.com/workspace/gmail/api/auth/scopes).

Google classifies mailbox-reading scopes as restricted and documents verification and a security assessment for server storage/transmission of restricted data. Establish the applicable personal/testing or public-distribution path before promising a public launch. A private pilot is not evidence of public approval. Hosted mail is the recommended architecture for Mac/web parity and scheduled delivery; a local-only alternative changes the product scope and does not automatically remove every OAuth requirement. [Google verification requirements](https://developers.google.com/workspace/gmail/api/auth/scopes).

Update the existing “Concourse does not read your email” copy only for accounts enabling Mail; keep the distinction clear for send-only users. Define retention, disconnect and account-deletion behaviour before ingesting real mail. A proposed default is cached metadata, bodies fetched as needed, attachments fetched on demand, and explicit offline pinning on Mac.

### Retrieval and state changes

Start with paginated recent Inbox, Sent and Drafts metadata, then backfill and retrieve bodies on demand. Persist the mailbox history checkpoint as an opaque value. Apply `history.list` changes, including label changes and deletions. An expired history checkpoint returns 404 and requires rebuilding the affected cache; preserve usable stale data until recovery is ready. Establish a checkpoint/backfill/replay sequence so mail arriving during the first import is not missed. [Gmail synchronisation guide](https://developers.google.com/workspace/gmail/api/guides/sync).

For hosted accounts, use authenticated Pub/Sub delivery with Gmail watches. Renew watches daily, respecting the returned expiry; Google requires renewal at least every seven days. Coalesce notifications and use a periodic catch-up task for missed signals. Do not use the notification’s history ID as proof that all intervening changes were applied. [Gmail push guide](https://developers.google.com/workspace/gmail/api/guides/push).

Expose paginated thread lists, message retrieval, draft CRUD, label operations, attachment retrieval and search through first-party APIs. Every operation carries the account ID and checks ownership. Keep the provider search path for uncached history; offline search must say it searches downloaded content.

### Sending and drafts

Create a durable operation before dispatch. Use the account’s authorised sender, MIME-safe recipients/headers and attachments, correct reply headers and provider thread identifiers. Autosave local drafts promptly, synchronise revisions, and preserve a recoverable copy on conflicts.

Undo send is a short delay before calling the provider, not a promise to recall delivered email. On a timeout after dispatch, set an uncertain outcome and reconcile against Sent using available provider/RFC identifiers before offering another send. Gmail does not provide a general exactly-once sending guarantee. Preserve the existing booking sender’s rule against blindly retrying interrupted sends.

### Safe reading and offline behaviour

Sanitise HTML and render it in a separate, restricted reader with no app credentials or native bridge; never mount raw email HTML in the authenticated app DOM. Block scripts, forms, dangerous URL schemes and remote tracking images by default. Make remote-image loading explicit; if a proxy is introduced, defend against private-network fetching and unsafe redirects. Treat attachment filenames, types and previews as untrusted.

Use owner-scoped RLS for exposed metadata; private credentials and attachment storage; short-lived authorised download links; redacted telemetry. Test that third-party MCP credentials cannot read new mail tables. Local cache and drafts must be isolated by Concourse user and provider account, protected at rest as appropriate, and removed according to disconnect policy. Notes explicitly created from mail remain user notes unless separately deleted.

Offline Mac release requires downloaded reading/search, local draft creation/editing, a visible queued outbox, safe reconnect, and conflict recovery. A hosted webview alone does not satisfy this gate.

## 7. Outlook and Microsoft 365

Add a Microsoft provider using delegated Graph permissions for the signed-in person. Plan personal Outlook.com and work/school Microsoft 365 as separate test cases. Use `openid`, profile identity and offline access, then Calendar/Mail scopes only for enabled features. Mail writes require `Mail.ReadWrite`; sending requires `Mail.Send` separately. Calendar editing needs `Calendars.ReadWrite`. Tenant policy may require administrator approval even for a personal connection. [Microsoft permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference).

Graph message deltas are per folder. Preserve opaque next/delta links, synchronise folder changes, and handle moves as changes across folder views. Use immutable IDs consistently where supported to avoid breaking message links when mail moves within a mailbox. Keep Gmail labels and Outlook folders/categories distinct internally. [Message delta guide](https://learn.microsoft.com/en-us/graph/delta-query-messages), [immutable IDs](https://learn.microsoft.com/en-us/graph/outlook-immutable-id).

Use supported v1.0 calendar-view delta endpoints for the ranges/calendars they support. Validate non-default and shared calendar support explicitly: do not assume a beta example is a production contract. Use paginated range reconciliation as a fallback where suitable delta support is unavailable. [Calendar-view delta API](https://learn.microsoft.com/en-us/graph/api/event-delta?view=graph-rest-1.0).

Graph subscriptions need renewal and lifecycle recovery. Shared/delegated mailbox notifications have permission limitations; treat shared mailboxes, room resources and delegated calendars as a later compatibility milestone rather than promising them with basic Outlook login. Validate callback challenges/client state and recover missed notifications. [Outlook change notifications](https://learn.microsoft.com/en-us/graph/outlook-change-notifications-overview).

Build a provider conformance suite now: list sources, fetch range/page, apply delta/deletion, refresh credentials, draft/reply/send, move/archive, and recover uncertain operations. Implement Gmail first and run the same behavioural suite against Graph when Outlook is added.

## 8. Delivery plan and release gates

Effort below is a rough engineering estimate for this repository, not a delivery commitment. Estimates assume one experienced engineer, existing hosting, no wholesale application fork and staged Mac/web delivery. External verification and review time are excluded. Re-estimate after the account/sync and rendering spikes.

| Phase | Work and likely files | Exit gate | Rough effort |
| --- | --- | --- | --- |
| 0 — Restore calendar trust | `CloudSync.swift`, Swift fixtures, API history contract, clear coverage/error copy | Yesterday survives sync/restart/offline; future meeting offers remain correct; limits are visible | 2–4 engineering days |
| 1 — Accounts and retrieval | Provider accounts/credentials adapter; `calendar.ts`, `google.ts`; range API; schema/coverage/checkpoints; source settings | Two Google accounts and secondary calendars; old clients still work; no silent truncation; failures isolated | 2–3 weeks |
| 2 — Complete Calendar | `CalendarService`, `CalendarWorkspace`, web `meeting-workspace`; occurrence links; native source controls; grid/editor/RSVP; durable updates | Faithful history and all-day/multi-day events; recurrence edits and source permissions; keyboard/VoiceOver; provider parity | 3–5 weeks |
| 3 — Gmail pilot | Independent mail consent; mailbox entities/jobs; MIME/renderer spike; read/search/labels; web Mail workspace | Real multi-account reading/triage; restricted-data rollout path established; missed updates recover | 3–5 weeks |
| 4 — Gmail daily use | Drafts/composer/attachments/outbox; snooze/scheduled send; native mailbox/cache; notes/calendar links | Draft loss and duplicate-send scenarios pass; offline Mac workflows; sustained daily-use trial | 4–7 weeks |
| 5 — Outlook | Graph account/provider; folder/delta model; subscriptions; parity testing | Outlook.com and Microsoft 365 pass supported-feature conformance suite | 3–5 weeks |

This is a several-month product programme. A useful Calendar repair ships early; a first-class mailbox should not be represented as a small addition to the current booking sender. The phases overlap only where their dependencies are already stable.

### First implementation slices

1. **Calendar history regression and repair.** Both Mac filters, cache restart, no past reminders. No schema migration needed for this first repair.
2. **Range and coverage contract.** New endpoint plus pagination, per-source status, server tests and backwards compatibility. Replace “empty” with explicit loading/partial/unavailable states.
3. **Account identity and independent source preferences.** Provider identities, source-qualified IDs, native connection summary, booking-availability separation and legacy note-link mapping.
4. **Provider workers.** Google incremental sync and range backfill, checkpoints, leases, subscription renewal and recovery telemetry. Remove full refresh work from page requests.
5. **Faithful Calendar model and views.** All-day dates, recurrence, overlaps, time-grid and proper detail state before general event mutations.
6. **Calendar editing.** Version-aware CRUD/RSVP and recurrence scope, guest notification semantics, conflict recovery, write-permission consent.
7. **Gmail connection and safe read path.** Scope/identity upgrade, ingestion, private bodies/attachments, renderer and search. Then composer/delivery in a separate slice.

Update `docs/CLOUD.md`, `docs/SELF-HOSTING.md`, shared contract fixtures and account copy as capabilities ship. Preserve the signed bundle identity and `make` build process. No change to dictation correction behaviour is needed.

### Acceptance matrix

| Scenario | Required result |
| --- | --- |
| Yesterday, last month, a year ago | Correct selected-source events; fetched on demand; explicit unavailable coverage when offline |
| More than 750 events / 25 calendars | Pagination or explicit supported-limit state; no silent data loss |
| Work + personal + shared calendar | Source provenance retained; reconnect one without losing others |
| Same event copied between accounts | Sensible presentation group; each source remains filterable and mutations target the chosen copy |
| Same title/time, genuinely different events | Both retained |
| All-day, midnight crossing, Sydney DST | Correct dates, durations and day placement |
| Recurring instance moved/cancelled | Correct occurrence; note link survives a move; other occurrences unaffected |
| Provider fails halfway through pagination | Old complete cache survives; incomplete new coverage is not labelled complete |
| Watch expires / duplicate or missed push / stale cursor | Automatic repair with no permanently missing events or mail |
| Disconnect / sign out / another user signs in | No cross-account cache, thread, draft, attachment or credential exposure |
| Edit calendar or draft in provider and app | Version conflict detected; recoverable choice rather than silent overwrite |
| Mail arrives during initial import | Appears after replay; no ingestion gap |
| Reply from unified inbox | Correct receiving account, recipients and thread |
| Send times out after provider acceptance | Uncertain state/reconciliation; no automatic duplicate |
| Malicious HTML or attachment | No script/native bridge/session access; remote resources obey policy |
| Queued send while offline/asleep | Visible queue; scheduled server work survives client shutdown; cancellation checked before dispatch |
| Third-party MCP session | Existing authorised notes/agenda only; no new mailbox privileges |

Use synthetic fixtures and test accounts for mutation tests. Extend Swift workflow tests, web unit tests and database integration tests; exercise ownership/RLS with real distinct test users and third-party tokens. Add Mac and browser interaction tests for compose, date navigation, keyboard focus and error recovery. Run `make build` and the relevant filtered tests while iterating; complete repository-required checks before release.

Suggested measurable targets, to validate rather than claim today: cached calendar/mail navigation under 200 ms at p95 on target hardware; visible cloud changes within 60 seconds at p95 under healthy provider delivery; fallback reconciliation within five minutes for active accounts; no missing fixture events, lost acknowledged drafts or duplicate sends in fault-injection trials. Instrument counts, lag, coverage and failure classes without logging message bodies or event descriptions.

## 9. Decisions and limits to carry into implementation

Recommended defaults are Gmail first, both Mac and web, hosted provider sync, native Mac calendar and eventual native Mail, primary sender before aliases, visible-period-first history loading, and no mailbox access for existing MCP clients. They make the plan concrete without requiring account changes now.

The first pilot should establish which Google accounts/calendars are needed, typical mailbox size, and whether Outlook means a personal account, work account or shared mailbox. Confirm the hosted-mail retention/verification path before ingesting a production mailbox. These affect rollout and sizing, not the immediate calendar-history repair.

Operational work includes job hosting, database growth, private attachment storage/egress, provider quotas, watch renewal, encryption-key rotation and recovery support. Measure a representative pilot’s messages/day, bytes fetched, API calls and sync duration before setting a cost budget; current evidence does not justify a dollar estimate.

The review establishes source-level failure paths and an implementation sequence. It does not establish that the installed/deployed versions match this checkout, that any given provider grant is valid, or that a particular open-source component passes the proposed runtime tests. Those are explicit implementation verification tasks.
