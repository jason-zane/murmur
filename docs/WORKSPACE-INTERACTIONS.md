# Concourse workspace commands

Concourse is one workspace for mail, calendars, notes, booking and dictation. The
command hierarchy must follow the task rather than each screen inventing its own
layout. This applies to the Mac and authenticated web app; public booking pages
keep their guest-facing layout.

## Shared rules

1. Navigation, account context and period navigation stay leading. Page creation
   and workspace-wide commands trail in the top header.
2. Selected-content actions sit above that content. Frequent actions are visible;
   less frequent actions have one scoped More disclosure. Do not duplicate visible
   actions in More. Separate destructive actions from editing/export actions.
3. A command names its actual outcome: New note, New message, New event, Record
   meeting. The web explicitly opens the Mac for capture instead of pretending it
   can record. Sender and destination account context remain visible when relevant.
4. Optional explanations appear on hover or focus and dismiss with Escape. Durable
   errors, unsaved work and connection status remain visible when they affect the
   task. Instructions do not consume a permanent toolbar row.
5. Web disclosures use ordinary buttons, expanded/controlled relationships and
   native Tab order. Escape returns focus to the trigger; clicking or focusing
   outside dismisses; only one More disclosure remains open. Native controls use
   system Button/Menu/Toolbar and SDK help.
6. Narrow layouts wrap trailing commands and retain source/context navigation.
   They must not hide controls merely to preserve a desktop composition.

## Placement and connected outcomes

| Workspace | Page commands | Selected-content commands | Connected outcome |
| --- | --- | --- | --- |
| Today | New note / Record meeting on Mac; Open Mac to record on web | Meeting or note-specific actions | Calendar context can lead into its note |
| Calendar | New event; Record meeting on Mac or Open Mac to record on web | Event review/edit actions above event details | Attendees, calendar and note context stay attached |
| Mail | New message | Reply, Reply all, Forward, Archive, Unread, Star, Bin, Create note; scoped More | Create note preserves the thread; explicit Open note crosses into Notes |
| Notes | New note | Edit/Save/Cancel, Copy, scoped Pin/Export/Delete | Notes save in Concourse; unfinished browser edits recover locally |
| Booking links | New meeting type | Link sharing, availability and meeting-type actions stay with their object | Calendar destination, guest details and note template remain part of the booking |
| Dictation | Open Dictation on Mac on web; dictation settings/history commands on Mac | History-item commands | Capture and insertion remain Mac capabilities |
| Connected apps | Account settings or setup guidance | Connection-specific recovery and permissions | Explain verified permission/status, without promising reconnection resolves every error |
| Settings | Account context | Scoped account/data controls with explicit confirmation | Product identity remains separate from provider funding/permissions |

## Reusable implementation

- Web `WorkspaceHeader` defines context and trailing command placement.
- Web `CommandButton` provides optional space-free focus/hover help.
- Web `ItemActions` provides the shared scoped disclosure and dismissal behaviour.
- Mac `WorkspaceCommands.swift` defines corresponding native commands, More menus,
  trailing toolbar spacing and adaptive selected-content rows using design tokens.
- Existing colour/typography/component tokens remain the visual source of truth.

## Boundaries and next product work

Placement does not establish feature parity. Web mail replies are inline; native
mail replies still use a sheet. Web saved email drafts support Concourse and Gmail;
native drafts still need that same cloud contract. Invitation and follow-up review
remain explicitly synthetic where only the prototype is enabled. Provider choice,
audio services, account eligibility and migration/onboarding remain separate work.
No UI label should imply a synthetic flow is live AI or that a save sent an email.

## Primary references

- [Apple: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Apple: Menus](https://developer.apple.com/design/human-interface-guidelines/menus)
- [Apple: Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [W3C: Tooltip pattern](https://www.w3.org/WAI/ARIA/apg/patterns/tooltip/)
- [W3C: Toolbar pattern](https://www.w3.org/WAI/ARIA/apg/patterns/toolbar/)

These inform the interaction rules. They do not certify Concourse's accessibility
or require custom web controls to imitate every native toolbar behaviour.
