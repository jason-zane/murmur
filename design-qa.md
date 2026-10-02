# Shared workspace web design QA

Final result: passed for the bounded Mail / Notes / Booking web command migration.
This does not establish full-product feature parity or accessibility compliance.
The preserved native checkpoint is 2ebc659 (build 45); its independent evidence is
under `audit/shared-native-controls` in the task workspace.

## Source and actual rendering

Before and after screenshots were captured in this run from the real MailWorkspace,
Library and Scheduling components, in an owned headless browser on local port 4317.
All content was synthetic. Desktop viewport: 1440 × 1000. Mobile: 390 × 844.
Files are under `/Users/jasonhunt/Documents/Codex/2026-10-01/task/audit/shared-web-controls`.
`review.html` presents the original screenshots together; every accepted screenshot
was opened and inspected. Mail/Booking page comparison states match. Notes retains
the same two source notes, but pin metadata reflects the synthetic command test.
No comparison claims pixel fidelity across a changed interaction state.

## Findings and fixes

- P1: mobile Booking More initially clipped past the left and bottom edges. The
  shared disclosure now measures its anchor, clamps to the viewport and opens
  above where needed; all edges checked and corrected screenshot inspected.
- P2: Notes duplicated New note in the list and reading pane; one trailing page
  command now matches Mail and Booking. Recoverable-draft help is on demand.
- P2: Notes edit/save/cancel lived apart from Copy/More; selected commands now share
  the row above the note. Back stays leading. List headings reflect All/Pinned notes.
- P2: Booking creation was below an oversized share panel; creation now uses the
  page header, and sharing remains a compact object-scoped row. Mobile item actions
  also trail, instead of falling to the leading edge.
- P2: Mail More duplicated visible Unread/Bin commands. The shared scoped disclosure
  retains the less frequent spam/restore/label commands, with consistent dismissal.
- A single page h1 with a selected note h2 preserves visual typography while making
  the heading hierarchy explicit. Full screen-reader verification remains unrun.

## Visual checks

Existing palette, DM Sans/system typography, indigo accent, component radii and
spacing tokens retained; no new assets or decorative images. Creation commands
trail, context leads, selected-item commands sit above content. Desktop and mobile
screens inspected for wrapping, clipping, menu visibility, labels, context and empty/
error states. Native window controls were not taken over during the user's call.
No remaining observed P0/P1/P2 visual issue in these captured states.

## Interaction checks

`cdp-ui-checks.log` records the final passing synthetic run. Focus help and Escape;
Tab into menus; Escape to trigger; close after command; Notes Edit/Cancel and mobile
Back; Booking Edit/Cancel, new/cancel and repeated rejected saves with edits retained;
inline web Mail reply with its source thread and From chooser; mobile overflow;
Notes empty and error states. All API writes rejected by the owned test transport:
exactly two attempted Booking writes, zero provider writes/sends. Earlier CLI
verification attempts stalled and were superseded by the owned headless Chrome CDP
run; failures in that test harness are not counted as passed application checks.

`npm run check`, `npm test` (337 passed, 2 existing skips), and `npm run build` pass.
No new tests mirroring CSS/component internals were added.

## Explicit limits

Authenticated Calendar/Today/Connected apps/Dictation/Settings headers now share the
component and pass type/build checks, but their web rendering is unverified in this
batch. Live Booking confirmation/reschedule/cancellation, provider permissions,
Gmail writes and production user data were not exercised. Native keyboard/menu/
VoiceOver and foreground tooltip QA await a safe foreground preview after the call;
this is not a claim that the Mac is locked. The prepared signed native build remains
uninstalled. Native inline replies and Concourse/Gmail draft parity remain product
work; the web prototype does not imply live AI invitation or follow-up generation.
