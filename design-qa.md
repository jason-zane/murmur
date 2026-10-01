# Selected workspace design QA

**Passed for the bounded web shell, Notes/document/review and familiar Mail-pane implementation.** This is an implemented local web checkpoint, not an installed native update or a claim of benchmark feature parity. Ancestor: `0128c04`; branch: `codex/concourse-audit-fixes`. The original dirty checkout is preserved.

## Reference and comparison method

Jason approved our judgment: Calm Notes Workspace (option 3), with familiar Mail panes from option 2. The retained references are [Notes](docs/design/screenshots/reference-notes.png) and [Mail](docs/design/screenshots/reference-mail.png), each1487×1058 generated pixels. These are visual concepts with synthetic content, not screenshots of implemented features.

Actual renders were captured in the isolated Codex in-app browser at1440×1024 CSS pixels, density1. For the combined comparisons the references were normalised to1440×1024 (aspect difference under0.1%). Both frames show the original synthetic pilot scenario; the Mail concept has additional proposed features that are outside this bounded implementation. The full comparisons and a focused inspector crop were visually inspected together:

- [Notes reference + implementation](docs/design/screenshots/notes-comparison.png)
- [Draft inspector detail](docs/design/screenshots/notes-inspector-comparison.png)
- [Mail reference + implemented panes](docs/design/screenshots/mail-comparison.png)
- [Actual before + after](docs/design/screenshots/before-after.png), same viewport and original sample note. Before has no saved draft; after retains the previously saved draft and offers Continue review.

## Findings resolved

| Priority | Finding | Resolution / verification |
|---|---|---|
| P1 | Mobile source selection left the user below the evidence. | Focus and scroll to the selected excerpt; Back to draft review restores heading focus and the draft pane. Verified390px. |
| P1 | Loading errors appeared beside empty/setup language; failed conversations kept “Opening…” indefinitely. | Distinct load/error/empty states and conversation retry. Simulated failures, repeated retries and recovery verified. |
| P1 | Notes editing offered Save without a clear way to cancel. | Cancel edit, Keep editing and explicit Discard changes; verified retained recovery draft after reload and both cancel decisions. |
| P2 | Notes draft inspector was narrow compared with the approved reference. | Desktop inspector420px, notes list260px; intermediate widths reduce panes; mobile uses a single readable pane. |
| P2 | Existing document-toolbar margin introduced a50px gap. | Removed; actual Notes shares the list/canvas hierarchy and consistent header spacing. |
| P2 | Drafts and Outbox had silent empty views. | Explicit empty-state purpose and next action. |
| P2 | A personal-mail fixture had incorrect recipient context and an unrelated “related note”. | Correct recipient/sender; only known pilot/support fixtures offer a related sample note. Personal reply verified. |

No unresolved P0/P1/P2 visual finding remains within this web scope. A further review is required when adding native changes or the Mail calendar-action inspector.

Intentional differences: the preserved fixed suggestion and three evidence excerpts determine wording, rather than fabricated transcript timestamps or the concept’s bullet text. Optional recipients and all missing details remain explicit. Unchecked approval disables save; a prior saved draft says Update local draft. Working close/undo/review controls remain visible. Source excerpts replace the concept’s unavailable recording/transcript. Draft context does not invent history. Mail keeps existing compose/reply/forward/folder behaviour; proposed event detection and inline rich-text compose from the concept are not represented as working.

## Verification

- **Passed:** web TypeScript check and production build; Vitest25 files /252 passed /2 skipped. New preview tests verify no network/provider fallback, persistent sample drafts/notes, version conflicts, cross-tab overwrite refusal, account isolation and storage failure preservation.
- **Passed in actual UI:** desktop1440×1024, intermediate1024×768 and mobile390×844; no horizontal overflow in inspected Notes/Mail/review states. Keyboard Tab/Escape, full mobile navigation, note search/clear, reply sender context, composer Escape/reopen, Notes recovery/cancel, source navigation, local review save/duplicate prevention, staged regeneration, slow prepare/cancel retaining edits, Mail loading interruption on navigation and simulated load/conversation failures with retry.
- **Passed:** final browser console observation returned no errors or warnings. Semantic field labels, active navigation, status/alert announcements and visible focus indicators were inspected. Reduced-motion styles disable decorative motion. Scope is manual checks, not an accessibility certification.
- **Unrun:** VoiceOver, comprehensive contrast audit, hardware capture/dictation, live OAuth/mail/calendar/booking delivery, production database integration (the two skipped tests), full native suite and native screenshot review. No private meeting source or new AI/provider call was used.

## Reproduction and boundaries

From `web`, run `npm run dev -- --port 3210`. Development-only review is `/prototype/follow-up?note=launch&review=1`; actual Notes preview is `?view=library&note=launch`; actual Mail preview is `?view=mail`. Preview state controls exercise slow, empty and failure responses locally. The route is gated by `NODE_ENV` and unavailable in production. Real production components retain their default authenticated transports; the preview supplies browser-local transports and disables sending. Fixed follow-up generation does not consume edits to the separate sample document, and the UI states that limitation.

Confirmed Library deliverables: implemented Notes `libfile_f42faa2e215c8191bf90898845e5a4b0`, Mail `libfile_511b1124248c8191a57d1de73be13b92`, actual before/after `libfile_15a2300a9b0c8191bf551f0ebb2448bc`. Local original-file version attributes were applied.

The [capability/journey matrix](docs/WORKSPACE-JOURNEYS.md) tracks essentials, dependencies and acceptance scenarios. Next: inspect the staged native shell/Notes with synthetic preview; then source-grounded editable email invitation proposals. Provider authentication and Concourse commercial ChatGPT eligibility remain separate decisions.

## Shared/native styling follow-on

The native navigation now consumes the same 208px width, 40px row height, 14px navigation type and 17px brand token used by the selected web shell. Notes adds a visible New note action and All notes filter reset, clearer list title/item hierarchy and accessibility labels for the pin filter. The footer distinguishes Concourse account from Local workspace. Native semantic colours and existing note/capture/sync behaviour are retained. Generated Swift and CSS tokens come from `shared/design/tokens.json`; web render values are unchanged by this extraction.

- **Passed:** `make app SCRATCH=/tmp/concourse-audit-build STAGE=/tmp/concourse-design-stage`; debug bundle assembled and signed at `/tmp/concourse-design-stage/Murmur.app`. Build log is retained outside the repo in `../audit/native-design-build.log`.
- **Passed:** `make test SCRATCH=/tmp/concourse-audit-build TEST_ARGS='--filter SessionStoreTests'`: 6 Swift Testing tests, zero failures. The preceding XCTest adapter reports zero because these tests use Swift Testing; this is not a zero-test verification. Log: `../audit/native-design-tests.log`.
- **Passed again after token extraction:** web production build, TypeScript check, 25 Vitest files /252 passed /2 skipped.
- **Unrun:** native visual, keyboard and VoiceOver review. The staged bundle was not installed or launched. The web QA pass above does not certify the native render. Full native suite remains unrun.

This follow-on is deliberately bounded to shared styling and navigation affordances; it does not implement native Mail, AI authentication, recording changes or sending.

## Email invitation review follow-on

**Passed for the bounded synthetic web journey. Native rendered review remains blocked.** The existing Mail reader now exposes Review invitation for the known pilot fixture, using a reusable source/form review and a pure local proposal model. The button is available only in the developer preview with an injected fixture adapter; production detection, account settings and event creation are not implemented or implied. The fixture adapter has no network fallback or write action. No new route, provider connection or AI call was added.

The flow retains the exact original email excerpt, sender, mailbox, message and source stamp. It leaves dates, time zone, duration, attendees and destination calendar unconfirmed. Edits save locally without requiring completeness. Account changes clear the calendar and availability; editing a time cancels a pending check and invalidates its result. Busy-data failure says unavailable, not free; sample conflict blocks completion. A current clear sample check and an explicit checkbox are required to mark the same local proposal reviewed. Nothing is reserved, sent or added to a calendar. Local storage corruption and concurrent edits preserve the original data and require a deliberate choice before closing unsaved work. Reopening changed source retains edits but resets review and availability.

Actual Mail and the completed review were captured at the same1440×1024 viewport and source. The [full comparison](docs/design/screenshots/mail-to-invite-comparison.png) and [focused editor crop](docs/design/screenshots/invite-fields-detail.png) were visually inspected, along with [missing details](docs/design/screenshots/invite-missing-desktop.png), [conflict](docs/design/screenshots/invite-conflict-desktop.png), [intermediate width](docs/design/screenshots/invite-tablet.png), [mobile source](docs/design/screenshots/invite-mobile-source.png) and [mobile review](docs/design/screenshots/invite-mobile-review.png). This adds a modal review within the approved shell; it deliberately does not reproduce the concept's unverified AI/calendar side panel.

| Priority | Finding caught in actual UI | Resolution |
|---|---|---|
| P1 | Existing detail width constrained the new dialog editor. | Scoped980px dialog, full-width child, balanced source/form columns; inspected1440/1024/390px. |
| P1 | Date edits were not durable until the control committed its value. | Persist temporal input events immediately; edits verified through check/cancel/reopen and navigation. |
| P1 | Closing review initially returned focus to the page body. | Restore focus to the originating Review invitation button; Escape return verified. |
| P2 | Global form margins produced excessive gaps and pushed actions down. | Remove redundant margins within this review; scrollable constrained dialog and mobile stacked fields. |
| P2 | Mail initially flashed connection setup before loading. | Begin in loading state, preserving later error/empty distinctions. |

- **Passed:** production web build, TypeScript, 26 Vitest files /262 passed /2 skipped. Ten new domain/fixture cases cover exact evidence, missing details, wrong-account calendar selection, guest validation, skipped and repeated DST hours (including30-minute transitions), stale responses, review expiry, idempotence, source changes, storage corruption/quota and concurrent edits. Fixture checks cover clear/conflict/unavailable/cancellation and assert no network calls.
- **Passed in actual browser:**1440×1024,1024×768,390×844 with no inspected horizontal overflow; incomplete editing, guarded Enter before approval, close/Back/Escape, focus return, reload and Notes→Mail navigation recovery, account/calendar switch, conflict, unavailable data/retry, interrupted check, explicit Cancel check, human approval and disabled duplicate completion. Two-tab edits reject overwrite; Keep review open retains unsaved wording, explicit close discards only that wording, reopening restores the winning saved proposal. Final console error/warning observation was empty.
- **Unrun:** source-change and quota-failure browser controls (covered at domain/storage level), comprehensive accessibility/VoiceOver, live invitation detection, real busy-data coverage, calendar writes/sends, authenticated server persistence and production integration. No private source was accessed.
- **Blocked native render:** a direct staged executable process was attempted with `MURMUR_UI_TESTING=1`, a newly generated isolated fixture directory and `session:sample-launch`. The process did not remain running; its log contained no diagnosis. Separately, supported native screen discovery reported the Mac locked and unable to unlock, so no native screenshot or keyboard result was obtained. The installed app was not replaced or normally launched. Earlier native build and six storage tests remain the only native pass evidence.

Reproduce in development at `/prototype/follow-up?view=mail`, open Pilot launch check-in, then Review invitation. Choosing Work calendar,2 October2026 09:30–10:00 Australia/Sydney yields a sample conflict;12:00–12:45 yields sample clear. Travel calendar demonstrates unavailable data. The date is a test input, not an inferred confirmation. The local preview was restored after the production build.

Confirmed Library files: reviewed desktop `libfile_ba0c0e5547d08191a1008d795af5ee60`, mobile review `libfile_6dea161bf2d48191add8720e7bb2c4cb`, same-source comparison `libfile_16da7878d7dc8191a663a06577170b84` (original-file version attributes applied). Next work should validate the native render when screen access is available, then address authenticated action persistence and real provider/read-only coverage through isolated integration tests rather than adding further mock screens.

## Core follow-up persistence checkpoint

This batch changes the server contract, not the approved visual design; no new screenshots or native render claim. `GET/PUT /api/sessions/:id/follow-up` and its unapplied migration support owned-note follow-up drafts. Real PostgreSQL rollback-only tests pass owner/editor/AI separation, direct-write denial, exact evidence, incomplete edits, explicit review, idempotent retry, stale edits/sources and deleted-note hiding. Fourteen HTTP/schema tests run real requestAuth, CSRF, editor checks, body limits and error mapping with only Auth/database transport stubbed. Full web suite27 files/276 passed/2 skipped, build and typecheck passed. SQL rollback completion was independently confirmed: proposed table/schema absent and both synthetic users removed.

Limits: UI server saving not wired; database advisors, real-token HTTP/PostgREST and simultaneous-request tests unrun because the proposed schema was never committed to a persistent stack and no new credentials were authorised. Native visual QA remains blocked/unverified from the prior attempt; this batch did not retry native controls. No private notes, AI generation, send, event mutation or publication. See `docs/FOLLOW-UP-DRAFTS.md`.


## Notes review/save/conflict UI checkpoint

**Implemented locally; production feature disabled; real-token integration unrun.** Ancestor `1a14698`. The actual Notes component now opens the owned note through `GET/PUT /api/sessions/:id/follow-up` and renders its source, editable fields, missing details and explicit human review. The server-only `FOLLOW_UP_DRAFTS_ENABLED` flag defaults off and no environment file, deployed setting or database migration was changed. The development preview supplies a separate browser-local contract fixture to that same component. It has no AI generation, mailbox draft, send or network fallback.

Per-tab recovery retains incomplete and temporarily invalid unresolved-detail typing, base version and source evidence across Back/Escape/navigation/reload. Server validation still blocks invalid saves. Read-only/signed-out or an unverifiable current snapshot clears current approval while retaining wording. Save failures finish with a truthful unconfirmed status, not a stuck loading label. Aborted/disposed responses cannot replace newer work. Lost-response retries deduplicate; conflicts compare both wordings and require a deliberate choice before saving. Source changes retain old wording/evidence, clear approval and block save until a deliberate rebase/reselection. Exact excerpt staging preserves existing wording until accepted and offers current-view Undo. No address, date or owner is inferred.

Actual screens were visually inspected: [source note](docs/design/screenshots/notes-follow-up-source-note.png) and [reviewed draft](docs/design/screenshots/notes-follow-up-reviewed.png) show the same synthetic source/version at1440×1024; [conflict comparison](docs/design/screenshots/notes-follow-up-conflict.png), [changed source](docs/design/screenshots/notes-follow-up-source-changed.png), [unfinished draft](docs/design/screenshots/notes-follow-up-incomplete.png) and [mobile editor](docs/design/screenshots/notes-follow-up-mobile.png) show real rendered states. These are local component screens, not proof of live database/provider operation. The checklist QA note was created synthetically in the browser; the original pilot fixture was deliberately edited to test source changes.

| Priority | Finding | Resolution |
| --- | --- | --- |
| P1 | Focus/long forms could scroll the review header and source identity out of view. | Scoped height and independently scrolling source/editor panes keep the header visible; mobile stacks content in one scroll region with retained footer controls. |
| P1 | Over-limit unresolved-detail typing could be rejected by recovery before the user corrected it. | Working recovery accepts bounded unfinished typing; stricter server schema still blocks save/review. Actual21-detail input survived close/reload and showed a plain validation message. |
| P2 | New note selected visually but left the old note ID in the URL. | Update URL on creation; actual reload returned to the new note rather than the previous source. |
| P2 | Failed/denied refresh could leave historical approval visible; failed saves retained a saving status. | Clear effective approval when current access/source is unverified and finish save status as unconfirmed, retaining wording and recovery. |

- **Passed:** final clean web production build and TypeScript;28 Vitest files /292 passed /2 skipped. Sixteen new controller/transport cases cover local recovery (including over-limit details), repeated/aborted/lost-response saves, forced late completion, two-session conflicts/undo, current-source races, staged replacement, offline/401/403 boundaries, corrupt/quota/another-writer storage, disposed responses and malformed/wrong-source responses. The two existing skipped tests remain skipped; the real Auth/PostgREST suite is excluded and unrun, not part of these passes.
- **Passed:** real PostgreSQL rollback fixture rerun; separate cleanup query confirmed proposed table/schema absent and synthetic Auth users0. A separate static privilege/definer/race pass is documented in `docs/FOLLOW-UP-DRAFTS-REVIEW.md`; this is the implementer's review, not a second-person sign-off.
- **Passed in actual browser:**1440×1024,1024×768,390×844 with no inspected horizontal overflow; incomplete save, explicit reviewed save and duplicate-button disablement; Back/Escape focus return; source selection by keyboard Space; reload recovery, independent second-tab wording/conflict/recovery/choice/undo, source update/rebase with old wording retained, staged keep/replace/restore, cancellation with newer edits retained, read-only/signed-out disabled writes, empty source/no-match search and over-limit detail recovery. Final clean-tab console error/warning observation was empty. Controlled late server completion is guaranteed by the controller fixture; browser timing is not a concurrency proof.
- **Resolved check failure:** initial TypeScript run encountered duplicate generated `.next` declarations. Regenerating the build cache through a clean production build restored the final passing check; no source workaround was introduced.
- **Unrun:** real issuer tokens/PostgREST and concurrent DB calls, database advisors on a committed disposable schema, second-person SQL review, VoiceOver/comprehensive accessibility and real provider/private-source QA. Native render remains blocked/unverified from the prior attempt; no native controls, installed app, Auth grants, live mail/events or AI calls were used here.

Library delivery passed for all four selected screenshots. Initial service discovery failed DNS/TLS because host Python lacked a default CA file; the existing certifi bundle restored verified TLS for that child process only. Service discovery then reported prepared uploads unavailable for this connection, so the supported host-upload create fallback was used. No prepared session had been created. All per-item results succeeded and the current metadata helper applied local identity/version attributes. Confirmed IDs: reviewed `libfile_455680afde7c8191be4e9cec8a6cca28`; conflict `libfile_febc1fdee7ac81919d2835af722ee837`; source-change `libfile_171fc7b2fc3c819190ef991453252975`; mobile `libfile_feb0c83b54f881919683b0630447ecb8`. No TLS verification, global settings or account permissions were changed.

Reproduce with `npm run dev -- --port 3210`, `/prototype/follow-up?view=library&note=launch`, Review follow-up. The preview state control exercises slow/read-only/signed-out responses. For the complete screenshot scenario, create a personal note with “Sam confirmed the checklist is complete. Share the checklist update with sam@example.invalid.”, select that exact evidence, manually enter recipient/wording, check human review and save. In a second tab retain different wording, save another revision in the first, then save/refresh the second to compare. Editing the source note triggers the version-warning/rebase path. A fresh browser profile starts with seed fixtures and no saved QA drafts.

Release recommendation is pending the approved ephemeral stack/token/concurrency/advisor action described in `docs/FOLLOW-UP-DRAFTS-REVIEW.md`, a second reviewer and explicit migration/feature/deployment decisions. Next functional scope after that gate: real mail/calendar interaction completeness and source-aware invite persistence, using existing authorised read coverage rather than more disconnected mock screens.


## Notes review corrections after independent review (1 October 2026)

Bounded follow-up to `deb77d5`: the proposed source-revision trigger covers direct owner writes; both draft API methods are disabled before Auth/RPC unless the server flag is exactly true; excerpt replacements over 10,000 characters preserve prior wording/recovery; clean refresh/reload adopts the latest saved document while actual unsaved edits conflict. Version 2 recovery stores the clean baseline and retains legacy version 1 copies conservatively.

Validation: 28 unit test files, 304 passed and 2 skipped; Next production build and TypeScript passed; real PostgreSQL rollback-only role/ACL fixture passed, including direct write/upsert/revert/metadata/delete/restore and normal RPC retry revisions. Cleanup verified no draft table, private schema, trigger or synthetic fixture users persisted. Regressions initially reproduced the disabled-flag, oversized replacement and clean-refresh failures. Existing late-save/cancel/navigation recovery, two-session conflicts, source mismatch, storage errors and read-only/unauthenticated checks remain passing.

Rendered UI recheck is **unrun for these corrections**: this execution environment exposes no supported browser/desktop tool, `agent-browser` is absent, and the earlier browser/server session is unavailable. Previous desktop/mobile screenshots belong to the earlier checkpoint and are not evidence of these amended interactions. No native rendered or issuer/concurrent-DB integration result is claimed. Those checks and independent re-review remain release prerequisites; no migration, production feature flag or deployment was applied.
