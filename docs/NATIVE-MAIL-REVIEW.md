# Native Mail, 2 October 2026

The installed `fd2ce00` reader blocked remote images by default even though web
Mail already loaded them automatically. Native Mail now uses the web policy:
load HTTPS and embedded images when opening the message, with a message-scoped
Block remote images control. Sender scripts remain disabled, the cookie store is
non-persistent, and the document keeps its restrictive CSP and no-referrer policy.

Compose and infrequent Mail options use the standard SwiftUI window toolbar.
Common reply, forward, archive, read, star and bin actions appear above the reader
with named accessibility controls and tooltips. Inbox rows show a quieter account
label and less preview text. Downloaded content stays visible while loading.

All-inboxes requests overlap, with a maximum of three active mailbox requests.
Successful accounts update even when another account fails; downloaded content for
the failed account remains visible with its error. Cancellation, owner changes and
older reader responses cannot repopulate a conversation after navigating away.
The synthetic four-account test uses 150 ms per request and completed in about
323 ms, compared with 600 ms of serial network waiting. This is a synthetic
transport measurement, not a production latency guarantee.

The native composer now offers a From selector. Switching preserves content,
recipients and attachments, but removes Gmail draft/revision/thread identifiers
belonging to the old account. A provider-backed original keeps its local recovery
copy and its Gmail draft. The body has an accessible name and an empty placeholder.
Escape saves locally before closing.

## Validation and limits

`make test TEST_ARGS='--filter Mail'` covers image-document security, account
identity, local recovery, bounded concurrent loading, partial failures, ownership,
cancellation, stale reader responses and sender changes. The isolated debug Mail
preview uses the real SwiftUI workspace and WebKit reader, a separate sessions
directory, synthetic accounts and read-only fixture transport. It never accesses
real mail credentials. Gmail saves and sends are disabled there.

Launch the preview with the repository's documented launcher:

```sh
open -n --env MURMUR_UI_TESTING=1 --env MURMUR_SESSIONS_DIR=/absolute/fixture/sessions \
  --env MURMUR_PREVIEW_OPEN=mail /absolute/staged/Murmur.app
```

Live Gmail writes, sending, VoiceOver and dictation capture are outside this batch.
Native replies still use the composer sheet. Native draft recovery is on this Mac
plus explicit Save in Gmail; hosted web Mail already has Concourse/Gmail draft
persistence. Native inline replies and cloud draft parity, compact Booking Links,
and the owned Note → review → editable Mail handoff remain subsequent batches.

The native changes use Apple SDK components and existing system fonts/SF Symbols;
no third-party design kit or font assets were added. Design reference:
[Apple toolbar guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars).
