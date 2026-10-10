# Shared native controls checkpoint — 2 October 2026

This bounded native batch applies one command hierarchy across Today, Notes, Calendar, Mail, Dictation history and Connected apps. `WorkspaceCommands.swift` supplies SDK command buttons, scope-named More menus, a trailing toolbar area and an adaptive selection bar. Equivalent creation/task actions now appear at the right; selected-note controls sit together above its document; New note is no longer repeated in the sidebar/empty pane. Calendar creation joins Record meeting in the toolbar, while date/source navigation stays near the calendar. Dictation has Dictation settings and confirmed history deletion instead of an unrelated New note. Connected apps uses the same toolbar for Setup guide. Row `ItemActions` delegates to the shared More menu. The active meeting strip preserves Show notes across workspaces. Window titles identify the workspace.

The first native render exposed that grouping the creation commands kept them left; separate SDK toolbar items fixed placement. Matched before/after six-screen review and focused-region comparisons passed; see `design-qa.md` and the task's `audit/shared-native-controls/` artifacts. No installed app replacement or remote publication occurred during this checkpoint. Original dirty checkout is preserved (125 records).

## Verification

`make test SCRATCH=/tmp/concourse-native-polish-scratch TEST_ARGS='--filter "Mail|WorkflowTests|CalendarWorkspaceStoreTests"'`: 57 individual tests passed, three opt-in model/transcriber smoke tests skipped; 60 cases in 11 suites. Native debug build, signed release build, signature verification and synthetic MCP smoke pass. Final staged bundles must use the checkpoint commit stamp before installation; paths/logs are in the task artifact.

Actual synthetic UI passes: trailing workspace controls, six matched minimum-width screens (1040 × 672 window), wide Today, Mail HTTPS/embedded images, repeated Today/Mail navigation, repeated Create note producing one source note, explicit Open note, Edit/Done, interrupted edit/navigation/reopen recovery and repeated Create note preserving the edits. Fixture durable files asserted. No private meeting source, provider write/send, AI call or account grant.

Unrun: native keyboard/VoiceOver and expanded menu/tooltip interactions, actual capture, authenticated embedded Booking, web/mobile alignment, real Gmail draft saving/sending. Full slow native suite not rerun. Three model smoke checks require their opt-in environment; no provider/model setup created here.

## Image and responsiveness status

Installed `/Applications/Murmur.app` remains `1613c65` build 43. It already contains the native HTTPS/embedded image-on-open policy, per-message Block remote images control, disabled sender scripts, restrictive CSP/no-referrer and nonpersistent cookies; current minimum-width fixture rendering confirms those images still work. Installed From chooser retains text/recipients/attachments while separating old mailbox draft/thread identities. Installed all-inboxes loading overlaps up to three requests, retains downloaded content during refresh/partial failures and rejects stale/cancelled/old-owner responses. The prior synthetic four-account/150-ms transport test measured about 323 ms versus 600 ms serial waiting; no live-network guarantee. This batch preserves those fixes and their affected tests. Live private image rendering and actual provider latency are not newly verified.

## Release and Git linkage

GitHub `master` was re-read through the official connector and remains `d201a0129f6cc54b24e911940c84d9f8b5236441`; web source matches the deployed release (`git diff 3859139 d201a01 -- web` is empty). Current master is source-deployable with the existing web-root/environment configuration and previously applied migrations; linking it does not include local native controls. The prior web release had 337 passing tests, two pre-existing skips and a successful Next build; these are historical checks, not new runs in this native-only batch.

Safe timing: parent can coordinate a deliberate Git-linked deployment of that existing web master separately from installing this native candidate. Keep production branch `master`, existing `web` root, environment and current production alias; verify the first commit/artifact before future automatic deployments. Linking can trigger an immediate deployment. No new UI requirement forces delaying linkage to the already-deployed web source, but do not present it as releasing these local native controls.

The Vercel connector's get-project read returned 403 for `jason-zanes-projects` (team `team_NnRv4M8T4zLCplpGVqRBk3YR`). No reconnect, token/scope/permission change or Git linkage was performed. Parent's authorised regular-Chrome route is still needed to verify current project configuration/link it.

PR6 remains draft at `1613c65`. Automatic approval review previously rejected ready-for-review as an external publication/notification action lacking explicit authorisation. No ready/merge/push bypass. Exact remaining publication approval after reviewing the final checkpoint: update draft PR6 with the local native controls, mark it ready and merge that reviewed scope. User has already authorised local iteration/tests and Mac installation; don't ask again for those permissions. Parent coordinates release timing.

Next bounded integration batch: apply the same command hierarchy to embedded Booking and hosted web; then native inline replies, Concourse/Gmail cloud draft parity and the note→review→editable Mail handoff. Do not claim those are implemented by this controls batch.
