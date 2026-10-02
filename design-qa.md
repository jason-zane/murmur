# Shared native command design QA

**Findings**
No remaining actionable P0/P1/P2 visual findings in the bounded native workspace-controls migration after the second iteration. This is not a full-product parity or accessibility certification.

**Source visual truth and rendered implementation**
Source: actual synthetic screenshots under `/Users/jasonhunt/Documents/Codex/2026-10-01/task/audit/holistic-design/`: `01-today-before.png`, `02-notes-before.png`, `03-note-detail-before.png`, `04-calendar-before.png`, `05-dictation-before.png`, `06-connections-before.png`. Implementation: corresponding `*-after.png` under sibling `audit/shared-native-controls/`. Existing app, synthetic notes/events, light appearance, inactive native window in both sources/after captures.

Matched native viewport: 1040 × 672 points, captured at 2× with system window shadow; every pair is 2172 × 1436 pixels. Each combined `*-comparison.png` places the actual source on the left and implementation on the right, normalised equally to 1086 × 718 pixels each. All six combined inputs were opened and inspected. Focused same-region pairs `01-today-focused.png`, `03-note-detail-focused.png`, `04-calendar-focused.png` were also opened and inspected to assess command placement, type and spacing.

Additional implementation evidence: `01-today-after-second.png` at a 1512 × 950 wide native window; `08-mail-after.png` at the minimum window with both embedded and remote fixture images rendered. Historical Mail source has a different viewport/selection/activation state; its comparison is contextual only, not a matched fidelity or typography claim.

**Comparison history**
1. Initial capture blocked. Console reported locked and foreground loginwindow; no fake screenshot substituted. When session changed to foreground Chrome, actual capture resumed with background-only preview.
2. [P1] First Today render left grouped creation commands on the leading side (the first capture was inspected in the tool result; its file was overwritten by the final matched sweep, so it is not claimed as a retained artifact). Separating root and Calendar native toolbar items, rather than a ToolbarItemGroup for creation commands, corrected the SDK placement. Window titles restored via standard unified toolbar configuration.
3. Recaptured all six matched workspaces and compared together with their source images. Today/Notes/Calendar creation commands and Dictation/Connections task commands consistently trail. No duplicate New note in sidebar/empty pane. Note commands share the selected-content row; Pin moves into its scoped More menu. Calendar leading date navigation and trailing source/search remain local.

**Required fidelity surfaces**
- Typography: system/DS families and document hierarchy preserved; matched note title/metadata and controls inspected in focused pair. No unexpected truncation in reviewed states.
- Spacing/layout: existing DS tokens, native toolbar controls and flexible spacing. Selection bar uses SDK ViewThatFits to preserve controls at narrower widths. Matched minimum-width six-screen review shows no new clipping; wide Today also inspected.
- Colours/tokens: existing indigo accent and native materials preserved. Inactive window controls are dimmed by macOS; this is not confused with unavailable actions. Recording/event write/AI summary generation are deliberately disabled in synthetic QA.
- Image quality: standard SF Symbols only, no new generated/decorative assets. Native Mail shows the embedded SVG fixture and the HTTPS remote fixture at minimum width; installed image policy/security is preserved.
- Copy/content: shared creation labels and scope-named More menus; no permanent command explainer. Note save wording remains Concourse/on this Mac, rather than falsely claiming native cloud draft parity. Preview-only synthetic disclosure is explicit.

**Interactions tested**
- Actual AX navigation across all reviewed workspaces without activating preview; foreground Chrome PID stayed distinct from preview PID in subsequent observations.
- Three repeated Today→Mail round-trips, cached reader/image control still present after each 200 ms observation. This is a synthetic responsiveness check, not production latency measurement.
- Create note twice → one fixture note, stays in Mail; Open note explicitly enters Notes with source mailbox/from/to/date.
- Edit→Done saves text. Edit→navigate away→Notes→select note restores edited text; durable fixture file asserted. Another Create note after editing reuses that note without overwriting it.
- Edit AXPress returned -25200 in one attempt while the editor visibly opened; acceptance is based on rendered editor state and durable output, not treating that API code as success.
- Existing automated checks cover owner/cancel/stale/repeated actions and editing conflicts. No live Gmail saves/sends, events, AI calls or private-source QA.

**Limits / follow-up polish**
Keyboard activation/tooltip interaction, VoiceOver and expanded More-menu interactions remain unrun because this verification kept the user's active foreground controls untouched. These are follow-up verification limits, not asserted failures. Native live capture, authenticated embedded Booking and hosted web/mobile alignment are outside this bounded migration. Native inline replies and Concourse/Gmail cloud draft parity remain next integration work.

**Implementation checklist**
Shared native command/button/menu/selection primitives implemented; duplicate controls removed; actual placement regression fixed and recaptured; matched full-view/focused comparisons inspected; affected tests/build/signature/MCP recorded in checkpoint. Keep PR6 draft until explicit ready/merge approval; coordinate installation separately from remote publication.

final result: passed
