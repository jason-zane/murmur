# Calendar and Mail validation — 30 September 2026

## Verified in this working tree

- Signed native build and `make install` passed. `/Applications/Murmur.app` was launched; `codesign --verify --deep --strict` passed and its executable SHA-256 matches the staged build. Previous bundle preserved at `/private/tmp/Murmur-before-workspace-20260930.app`. No active recording/finalising note was present before installation. Existing bundle identity and Apple Development signing identity retained.
- Full Swift suite passed: 100 tests in 19 suites, recorded in `/tmp/murmur-final-swift-tests.log`. An intervening run failed a meeting-recording test; the repeated full suite passed. Its exact failure was not retained, so no cause is claimed.
- After final changes, targeted native verification passed 24 tests in CalendarWorkspaceStoreTests, MailWorkspaceStoreTests and CloudSyncWorkflowTests. Includes offline recovery, account isolation, cancellation/idempotency, missing hosted endpoints and authoritative complete-empty calendar cache handling. The final pending-refresh persistence fix then passed all four calendar-store tests and was rebuilt, reinstalled and signature/hash verified.
- Final `npm test`: 190 pass, two existing skips, 19 test files. Includes Google OAuth owner-binding rejection before token exchange and safe native navigation.
- Final `npm run check` and `npm run build` pass.
- `npm run test:integration`: 25 tests pass against the isolated local Supabase stack. Rollback-only SQL checks cover range replacement/deletions, preferences, owner and MCP isolation, leases/checkpoints, cancellation reservation, push-channel secrets/renewal/recovery, dirty jobs and booking conflicts.
- MCP smoke verification passed lifecycle, pagination/search/resources, read-only defaults and revision-protected writes.
- Dependency audit reported no known vulnerabilities; `git diff --check` passes.

Native synthetic previews were visually checked for the four main destinations, Connected apps, signed-out Gmail setup and the optional welcome guide. The Mac subsequently locked, preventing final visual/keyboard acceptance of the latest onboarding changes or inspection of the launched installed app.

Earlier synthetic browser checks exercised desktop/mobile mailbox, account-aware reply, composer and calendar editing, all-day validation and week navigation. Intermediate screenshots: `/tmp/murmur-mail-compose.png`, `/tmp/murmur-mail-mobile.png`, `/tmp/murmur-calendar-week.png`, `/tmp/murmur-calendar-editor.png`. These are fixture checks, not live provider acceptance; the latest web setup changes compile but still need visual acceptance.

## Hosted release completed — 30 September 2026

Direct MCP lookup succeeded for project `olxjfdsslbpdvywsnzrc`, named Murmur, in organisation Murmur (`dxqglhelvchutaqnjiyi`). The MCP project/organisation list omitted it; list omission was incorrectly treated as an access failure. The original deployment record in docs/history/DEPLOYMENT.md identifies this organisation. The browser's signed-in jason-zane organisation was a different organisation. No human owner email was inferred from the app login.

All four new migrations applied successfully via MCP. Hosted rollback-only calendar/mail privacy, range preservation, deletion, checkpoint, push and cancellation checks passed; all five new tables have RLS. The matching backend deployed READY as `dpl_BTMrckn2qzsMUoEXaYaSraVmaueS` and the production alias is `https://murmur-rho-pied.vercel.app`. Public configuration now advertises workspaceVersion 2.

Runtime logs show repeated HTTP 200s for all three scheduled dispatch routes. Calendar metadata showed three complete jobs, four downloaded ranges, two active watch channels and no failed jobs. Native Connected apps loaded the authenticated hosted page, and Add another Google account opened Google's chooser using the new one-use handoff, without another Concourse login. Previous-week meetings loaded in the installed Calendar. Native Mail correctly offers Gmail connection because no gmail.modify grant exists yet.

A production-environment download for manual worker checks was rejected by automatic approval review because it requested more secrets than necessary. No such file was downloaded. Verification used read-only route/status logs instead; no worker verification remains blocked.

## Remaining acceptance

No live event edit, completed new Google consent or email delivery was performed during this release. Calendar read/history and push registration are now established against the existing connection. Use test accounts to verify historical/recurring events, multiple accounts, source selection, ETag conflicts, attachments, drafts, scheduled send/Undo and uncertain-delivery reconciliation. Incremental provider cursors, mailbox-wide offline import, rich editing, complete recurrence controls and other longer-term scope are tracked in CALENDAR-AND-MAIL-PLAN.md. Outlook is deferred. Passing local checks does not establish these unimplemented phases or live integration as complete.

## Follow-up refinement

Permanent Booking links and Dictation history navigation restored on native/web. Calendar now has a responsive Day/Week grid with pinned headings, opaque event surfaces and initial 08:00 scroll; synthetic native visual inspection confirmed these. Calendar status/time zone is disclosed from the toolbar. Same-range polls retain visible events; a dedicated in-flight refresh test passes. Setup now defaults to signing in and connecting Google accounts, with local use secondary.

Updated verification: 196 web tests pass (two existing skips), TypeScript and production build pass; 25 targeted native tests pass and signed app builds. Added browser-session handoff tests for allowlisted continuation, token consumption, owner mismatch, expired token and preserving another browser account. Hosted rollout subsequently completed as recorded above. Live Gmail authorisation and delivery remain user acceptance steps.

The follow-up signed build was installed and launched; signature verification passed and installed/staged executable hashes match. Installed UI inspection confirmed permanent navigation, connected account status and the refined calendar. The correct Supabase dashboard was reopened and again redirected to sign-in; left ready as a browser handoff.

Gmail setup subsequently reached Google's “Google hasn’t verified this app” warning under the owner's Google developer identity. No warning bypass or mailbox permission approval was performed. The consent tab is left as a user handoff. Google verification/security requirements for broad mailbox access remain an external release requirement; this is not a claim of completed live mailbox acceptance.


## Inbox and week-view refinement — 30 September 2026

The owner subsequently connected three live Gmail accounts. The installed native mailbox loaded the unified inbox and a formatted provider conversation. Account navigation now separates All inboxes from individual Gmail accounts, with account identity on unified rows and in the reader. Navigation, search and reader actions stay fixed; the list and reader scroll independently. Formatted bodies grow to their content height, retaining disabled message scripts and blocked remote resources.

Synthetic browser verification covered independent list/reader scrolling with the document and navigation stationary, account switching, desktop widths of 1512 and 1040 pixels, and a 390-pixel mobile reader with Back navigation. Long HTML expanded to 3909 pixels inside the reader. Temporary mock routes and components were removed before the production build.

Native week inspection used live historical events: adjacent meetings use full day width, coincident events use separate lanes, headers stay pinned, and the timeline opens at 08:00. Four placement tests cover independent overlap groups, chained overlaps, short-event display height and stable ordering/midnight clipping. All 19 targeted calendar/mail native tests pass. The final TypeScript check, 196 web tests (two existing skips) and production build pass; the layout detector reports no findings.

The user selected Concourse. Product-facing Mac/web copy, release filenames, current documentation, Google OAuth branding and the existing Supabase native client display name were updated. Stable bundle, Keychain, protocol, storage, deployment and OAuth client identities were preserved. Existing software also uses Concourse; this is the selected workspace name, not a claim of trademark or domain clearance. Google branding remains unverified. No email was sent and no live event was edited for verification.


Concourse refinement deployed READY as `dpl_HhhofZtqxMVBfYJLMMe4cQkZRkNS` to the existing production alias on 30 September 2026. Public configuration remains ready, workspaceVersion 2, with Google enabled. The signed Mac update was installed and its signature verified with macOS trust-store access; installed accessibility state identifies Concourse. Google Auth Platform confirmed “Branding changes saved”; existing client identifiers, redirects and scopes are unchanged.


Final isolated layout review identified hidden mobile account domains and a clipped reader action menu. Both CSS issues were corrected. Final deployment `dpl_5kUJvZuj2AKhGW3gHYpguXtvd7Z5` is READY on the production alias. Live browser verification confirmed all three accounts, a separately selected inbox, decoded snippets and the reader menu fully inside its column. Screenshot: `/tmp/concourse-mail-final.jpg`. Google branding verification and the live mutation/delivery checks listed above remain outstanding.
