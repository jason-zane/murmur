# Concourse workspace interaction design

The product combines mail, calendar, notes, booking and dictation. People should learn one way to navigate, find commands, make edits and recover, while each workspace keeps the controls its task needs. This specification replaces screen-by-screen toolbar decisions. The shared native controls are implemented locally for Today, Notes, Calendar, Mail, Dictation history and Connected apps. Their rendered cross-screen desktop/minimum-width review passed within the bounded native scope. Embedded Booking and hosted web alignment remain a subsequent batch.

## Shared hierarchy

1. Global navigation remains in the left sidebar. The window title identifies the current workspace, not the app name. Account/source and view/filter selection belong at the leading side of the relevant content header.
2. Equivalent creation commands live in a shared upper-right workspace action area: New note, New message, New event, New meeting type and Record meeting. Commands only appear where meaningful. Keep app-wide creation available through standard menu/keyboard commands without duplicating it in sidebar headers and empty panes.
3. A selected note, thread, event or meeting type exposes its common actions together, above that content at the right. Keep the distinction between creating an item and operating on the selection. A row's Join/Open/Copy remains beside that row because its scope is local.
4. One More menu for each command scope contains secondary commands: copy/export/share, history/appearance, then maintenance/destructive commands separated from other groups. Use consistent names, SF Symbols on Mac and the existing web icon set. Avoid nested menus except actual lists/options; preserve typed selectors for date, view, account and summary template.
5. Use native standard toolbar/material/hover/pressed/disabled controls on Mac. Share semantic tokens, icon meaning, grouping and labels with web; do not fake native chrome or introduce another palette/component family. Use concise text for unfamiliar connected actions, familiar icons with tooltip and accessible names for common actions.
6. Help is on demand via tooltips and accessible focus help. It does not reserve a permanent explanatory row. Feedback follows the action: pending, saved, recoverable failure, uncertain result. Feedback does not displace the main work indefinitely. Reserve modal confirmation for destructive/irreversible actions and preserve cancel/back/edit recovery.
7. Creation and review stay in context until the user chooses to open another workspace. Carry source and account context with every handoff. Sending/creating a live calendar event remains an explicit reviewed action.

## Command inventory and migration

| Workspace | Workspace creation/task actions | Selected-content commands | More / destructive commands | Current gap / next change |
| --- | --- | --- | --- | --- |
| Today | New note, Record meeting | Join meeting, Open note beside each row | Calendar status/setup secondary | Primary actions currently left; lower setup/help areas compete with main task. Use shared trailing toolbar. |
| Notes | New note, Record meeting | Edit/Done, Summarise/Refresh, Pin; Create email review next | Copy/export, history, reveal files; Move to Trash with recovery/confirmation | New note is repeated three times; document commands occupy separate rows. Consolidate scopes and make follow-through visible. |
| Mail | New message | Reply, Reply all, Forward, Create note; archive/read/star/Bin as thread actions | Formatting, web Mail, appearance/account/cache maintenance | Staged trailing toolbar removes duplicates; native inline reply and Concourse/Gmail cloud draft parity remain. Keep From chooser and thread visible when editing. |
| Calendar | New event, Record meeting | Event details, Join, Open/record linked note, Edit when writable | Calendar/source visibility and account settings; delete with appropriate confirmation | New event in body and Record meeting in left toolbar currently differ. Consolidate page actions; date/view/filter navigation stays local. |
| Booking | New meeting type, Copy booking link/guest preview | Edit, Share/Copy link, availability for the chosen type | Type maintenance; booking reschedule/cancel with explicit scope | Embedded web layout has its own header and oversized sharing/settings areas. Apply the same command hierarchy; signed-in visual audit still required. |
| Dictation history | Dictation settings/recovery where applicable | Copy/reuse beside the dictation | Clear history with confirmation | New note is unrelated as the sole history-page toolbar action. Do not invent new capture behaviour during this UI migration. |
| Connected apps | Setup guide/account management | Connect/Manage/Recover beside the chosen service | Advanced account/security settings | Keep permissions meaningful and local. Unify page header/actions; no implied reconnect guarantee. |
| Settings | Context-specific preferences | Live preferences or explicit Save/Cancel as actually supported | Import/export/reset with clear scope | Preserve existing state semantics; apply shared sizes/labels/menu and feedback rules, not blanket placement of every toggle. |

## Connected tasks

- Email → note: explicit Create note, source mailbox/sender/date retained, confirmation that it saved in Concourse, Open note only by choice. Repeated creation must preserve existing edits.
- Email → calendar: an editable suggested invitation with evidence, missing details/time zone, calendar/account choice and conflict status. Review before any event write.
- Note → email: Create email/follow-up → source-aware review → editable draft with From/recipients → save in Concourse and Gmail → explicit Send. Preserve uncertain details rather than filling them in. Native handoff is not implemented yet.
- Booking → calendar → meeting → note: same event/source context, clear confirmation and reschedule/cancel semantics. Do not imply synthetic booking fixtures are live.
- Dictation → insertion/recovery: preserve destination focus, editable output and recovery history; its capture model remains distinct from meeting recording.

## Acceptance for the first shared batch

- Today, Notes, Calendar, Mail and Booking put equivalent creation actions in the same upper-right area, with the same control sizing, labels and grouping principles. The selected object remains clear.
- No duplicate creation controls or permanent action-explainer row. Empty states guide people to a visible command or provide a necessary setup action.
- Common More menus use consistent groups and name their scope. Destructive commands are separated and have accurate recovery/confirmation behaviour.
- Desktop and minimum-width/native overflow remain usable. Web mobile adapts the same priorities. Keyboard focus is visible, tooltips dismiss without stealing context, and accessible names identify icon controls.
- Save/pending/error/cancel feedback uses shared primitives; repeated actions do not lose edits or submit duplicates. No send/event write is required for synthetic design QA.
- Capture before/after examples for multiple workspaces in one review, not a single toolbar screenshot. State what is implemented, mocked, failed or unrun. Do not call the full system shipped after changing one workspace.

## Primary sources

[Apple toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Apple menus](https://developer.apple.com/design/human-interface-guidelines/menus), [Apple buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Apple layout](https://developer.apple.com/design/human-interface-guidelines/layout), [NN/G usability heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/), [Fluent toolbar guidance](https://fluent2.microsoft.design/components/web/react/core/toolbar/usage), [W3C toolbar pattern](https://www.w3.org/WAI/ARIA/apg/patterns/toolbar/), [W3C tooltip pattern](https://www.w3.org/WAI/ARIA/apg/patterns/tooltip/).

These are research inputs. The shared hierarchy and migration choices above are Concourse design decisions. The W3C tooltip pattern is explicitly still in progress.

## Shared native implementation checkpoint

`WorkspaceCommands.swift` provides the standard command button, scoped More menu, trailing toolbar area and adaptive selection bar. Today/Notes expose one New note location; Calendar puts New event and Record meeting in the same trailing area; Dictation history exposes Dictation settings and a separated Delete all menu action rather than New note; Connected apps puts Setup guide in the shared toolbar. Note pin/copy/export/history/trash commands share one menu beside Edit/Summarise above the document. Calendar navigation/filter controls use the adaptive selection bar. Existing `ItemActions` delegates to the shared menu, so row actions use the same semantic control. The active meeting strip preserves Show notes across workspaces.

Native commands use standard SDK help and accessibility names/hints. Automatic focus popovers were removed because they can distract from keyboard activation. Native focus/hover/overflow must be visually verified, not inferred from compilation. Synthetic `home` preview now includes the existing Mail fixtures for cross-workspace QA; preview recording and summary generation are unavailable. Production behaviour and credentials are unaffected.

An initial capture blocker was verified as a currently locked console. The session later became interactive with Chrome in front, and background capture resumed without activating the synthetic preview. The first actual Today render exposed a left-positioned grouped toolbar; separate native toolbar items fixed it. Matched before/after screenshots for Today, Notes, note detail, Calendar, Dictation history and Connected apps are 2172 × 1436 pixels at a 1040 × 672 native window. Mail also renders at this minimum size, including both fixture images. Keyboard/VoiceOver and live provider writes remain unrun; full Booking/web alignment is not claimed.
