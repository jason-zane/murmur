# Completion audit

The delivery was **accepted as complete by the user on 9 September 2026**, with the final
two-person Google Meet check deferred. That check has not been recorded as passed.
The reported dictation failures and requested bar controls have been addressed.
Google Calendar consent and refresh passed on the live site. Native account sign-in and
initial synchronization passed after repairing an authentication callback crash. Account
settings are now present on both platforms.

| Requirement | Evidence | Verification limits and accepted deferrals |
| --- | --- | --- |
| Local dictation into the focused Mac app | Repeated AirPods capture failure and hanging empty results reproduced and repaired. Full native suite passed, then the user confirmed two consecutive real dictations insert text and return to idle | Continued daily use across target apps; second target app not separately recorded as checked |
| Optional live words and bar placement | Persistent settings, recording-free Preview, Top/Bottom/Left/Right visually checked, no shadow, eight-point edge inset; compact/expanded states checked | Multiple displays were not available for a live check |
| Detect and capture Google Meet in Chrome | Chrome audio aggregation and shared timeline; muted-call/delayed-audio policies tested; actual Apple meeting transcription fixture passed. Live test exposed recording on the preview screen; installed fix requires joined-call controls, and the visible preview remained idle | User accepted deferring a joined Meet after this fix with another participant: both voices, pauses, mute, call end remain unverified |
| Open scheduled meeting links in Chrome | Policies tested. A private Google Calendar event for 18:35 opened automatically in Chrome at 18:34:04 without clicking Join in the app | Passed for the installed app and live Google Calendar |
| Editable notes, transcript, revisions and recovery | Store, concurrent-writer, private-draft and conflict tests pass; earlier sample-library checks exercised the workflow | Latest-build native sync-issue disclosure check |
| Offline library with account sync | Atomic imports, per-account index; native workflow tests cover partial failure, retry, concurrent edits, sign-out, restart and isolation. Installed Mac → production → web → Mac passed. A further Mac edit saved while signed out appeared on the production web after reconnection | Signed-out operation verified; the Mac's network connection was not disabled |
| Useful on-device summaries | Source-checked actions and retained questions; actual Apple Intelligence short/long fixtures passed | Review real notes against source; fixtures do not guarantee general model accuracy |
| Local MCP | Installed executable smoke passed: lifecycle, pagination, search, resources, read-only access and protected writes | No additional local protocol gate identified |
| Authenticated remote MCP URL | Five local integration tests plus production OAuth consent and dynamic registration in Claude. All six read-only tools discovered; Search and Fetch returned the exact synced test note. List upcoming meetings returned the private test event with the correct Sydney time | Passed in Claude; ChatGPT is not separately checked |
| Vercel and dedicated database | Deployment dpl_7TpugBwNJhA7QRVaaeWzhicHVX2c READY; separate Supabase project, four migrations, Google and backend credentials deployed | Live integration results recorded below |
| Google sign-in and calendar | Actual Google sign-in and Calendar consent passed. Refresh, native agenda, automatic scheduled opening and the MCP calendar tool passed. Google Audience visibly reports In production | Public Google verification is separate from this personal-use setup |
| Build/test/install | 55 native tests in 11 suites passed with microphone/speech checks; five lifecycle tests rerun after bar changes. Web check, 13 existing tests and four OAuth-setup tests passed; production build READY. Latest native build installed with stable Apple Development signature | Coverage limits recorded above |
| Simple working name | Voice Notes in Mac/web, consent and MCP metadata; native/web labels visually checked | Final identity deferred at user's request |

See `DICTATION-VERIFICATION.md` for the reproduced failure and successful user check.
Deployment details are recorded in `DEPLOYMENT.md`. The hosted MCP URL is a verified live authenticated
Claude connection. Do not repeat passed test suites
without a new change, failure or concrete concern.

## Current account and live checks

The earlier desktop lock was resolved. A real browser sign-in exposed an XPC/MainActor
callback crash; the supplied user report confirms the same stack. The installed repair
passed two background-callback regressions and real native sign-in. The final focused
run passed ten authentication/sync tests, including rejected-session recovery and clearing
Calendar identity on sign-out. Real Sign in again returned the Mac to Synced.

Settings → Account and sidebar identity are installed on the Mac; `/settings` is deployed
and visually checked with the same real account and connected Google Calendar email.
Web sign-out is scoped to the current browser. The web's 17 tests and production build
pass. The labelled native test note appeared with matching content in the production web library.
The return web edit arrived in the installed Mac app. Claude then retrieved its exact text
through the production MCP Search and Fetch tools using normal OAuth authorization.
Browser control recovered after replacing a stale tab. Desktop and phone Account layouts
are verified; the mobile cloud-library row was corrected and checked at 390 × 844.
The live calendar test opened Meet automatically one minute before the scheduled start.
It exposed a pre-join recording bug: Chrome keeps audio devices open in its preview.
The detector now reads only Meet button labels off the main actor, requires joined-call
evidence for automatic capture, and ends a recording when the lobby returns. Its bounded
reader uses the existing Accessibility grant. The visible preview remained idle after
installing the fix. The user accepted deferring the actual joined-call check at closeout.

That test also exposed the on-device model copying an example timestamp into its summary.
The example was removed from the prompt, and generated source links are now restricted to
timestamps present in the original transcript or personal notes. Regression tests cover
the observed false link, valid hour-long timestamps and Unicode text. The focused native
run passed 36 tests across seven suites (three optional hardware/model tests skipped).
The stable signed build was installed and passed strict signature verification.

The disconnected-edit check also passed: the test note remained editable while the Mac
was signed out, then its fourth line appeared on the production web after normal sign-in.
The Mac is signed back in and Synced. The temporary Calendar event was removed after
the scheduled-opening check; its Meet tab is closed. Claude's successful read-only test
conversation is retained as a deliverable. No invitation was sent to another person.

The user accepted completion with the two-person Meet test deferred. This closes the
delivery; the coverage limits above remain documented rather than counted as passed.
Do not start another recording or repeat passing suites solely to close out this work.
