# Working on this repo

Read this before changing anything. It is written for a coding agent picking the project up
cold, and it is mostly a list of things that look wrong but aren't, plus things that look
fine and will bite you. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) has the build, signing
and release mechanics; this file is the judgement.

---

## What this is

Push-to-talk dictation and meeting notes for macOS. Hold **Right ⌥** (the default; any key
or mouse button can be added), talk, release, and cleaned-up text is typed into whatever
had focus. When a call starts, the app offers to record both sides into a note. Swift 6,
SwiftUI, no sandbox, everything on-device unless the person signs in to the optional
backend in `web/`.

It replaces a Wispr Flow subscription, so "as good as Wispr for daily use" is the bar —
not "a demo that transcribes."

Product name **Voice Notes**; bundle id `com.jasonhunt.murmur`, executable `Murmur`,
`Murmur.app`, `murmur://`, Keychain service `com.jasonhunt.murmur.cloud`. Those are TCC and
Keychain identity on installed copies and don't change.

---

## The one rule that matters

**`shared/dictionary-test-vectors.json` is the specification for correction behaviour.**

If you change how corrections work, change the vectors first, watch the tests go red, then
make them green.

```bash
swift test --filter VectorTests
```

The copy at `Tests/MurmurDictionaryTests/dictionary-test-vectors.json` is a copy, and CI
fails if it drifts. After editing the shared file:

```bash
cp shared/dictionary-test-vectors.json Tests/MurmurDictionaryTests/
```

---

## Things that look like bugs and are not

**`MainActor.assumeIsolated` will crash the process.** It does not check the claim, it
asserts it. Use `await MainActor.run` from any non-main-actor context. This took the app
down once already.

**`TextInjector` ignores the AX return value on purpose.** Electron apps, Chrome and most
terminals return `.success` from the `kAXSelectedTextAttribute` write and then silently
drop it. The AX path is only trusted when the caret can be observed to have moved.

**fn is not consumed by the event tap.** Swallowing it would break fn+arrow, fn+delete and
the emoji picker. Right ⌥ and Right ⌘ *are* consumed, because they have no other job.

**Parakeet is chosen only when its models are on disk.** `Settings.engine == .parakeet`
with nothing downloaded means Apple, plus one line in the dictation bar saying so. The
engine must never download behind a held key — 470 MB looks like a hang.

**The sync loop is 30 s and there is no "Sync now".** `CloudSync` also runs a pass when the
app becomes active and 5 s after a note changes; the button was removed because "now" is
implicit. The recovery for a note that didn't sync is **Try again** in Settings ▸
Connections. `CloudSync.state` (`SyncState`) is the only thing views read; signed out is
`.off` and shows nothing anywhere.

**The comparison window scene exists even with the developer switch off.** `SceneBuilder`
can't type-check an `if` around it; instead everything that *reaches* it is gated on
`Settings.developerMode` (the menu, ⌘D, `murmur://show`, the launch-time restore).

**`CaptureStatus` has no timer.** It reads `MeetingController.elapsed`, which ticks every
second, so its timed states ("Hearing you and the call" for 3 s, "No call audio yet" after
20 s of silence) advance for free. `callSilentSince` lives on the controller for the same
reason: views stay stateless.

---

## Code signing is load-bearing, not cosmetic

TCC stores a code-signing *requirement* per entry. An ad-hoc signature changes every
build, so the rebuilt binary stops satisfying the stored requirement — and the symptom
lies: the Accessibility toggle still shows as **on** while the app is untrusted.

The `Makefile` resolves an identity in this order: **Developer ID Application** →
**Apple Development** → ad-hoc. **Don't replace that with `--sign -`.** Reset a wedged
grant with `tccutil reset Accessibility com.jasonhunt.murmur` — never without the
identifier — then quit System Settings entirely before reopening it.
`Permissions.wasEverTrusted` is how onboarding knows to show that fix only when it applies.

---

## Build notes

**Always build with `make`.** It uses `--scratch-path` outside the source tree; a bare
`swift build` writes `.build/` into the repo. `make app` stamps `CFBundleShortVersionString`
(git tag, else short hash), `CFBundleVersion` (commit count) and `VoiceNotesSiteURL`
(`SITE_URL`) into the copied Info.plist — the checked-in plist holds placeholders.

**Never copy a scratch directory between paths.** The module cache bakes in absolute paths.

**`log` may be shadowed in the user's shell.** Use `/usr/bin/log` explicitly:

```bash
/usr/bin/log show --predicate 'subsystem == "com.jasonhunt.murmur"' --last 5m
```

**Don't run the `.app` out of the build directory** except in preview mode. The login item
and the Claude Desktop connection point at `/Applications/Murmur.app`.

**Preview mode** (`MURMUR_UI_TESTING=1` + `MURMUR_SESSIONS_DIR`, debug only) disables the
hotkey, cloud, calendar and detection and reads a synthetic library;
`MURMUR_PREVIEW_OPEN=settings:meetings|onboarding|session:<id>` raises a screen on launch
so it can be screenshotted without input. `Tools/preview-fixtures.py` makes the library.

**The full test suite takes ~20 minutes** (timeout tests). Filter while iterating.

---

## Design system

`Sources/Murmur/UI/DesignSystem.swift` defines every colour, size, radius, duration and
material token. **Views must not contain literal values.** If a component needs a number
that isn't a token, add the token rather than inlining it. `ComparisonWindow.swift` and
`DashboardHTML.swift` are developer-only and exempt.

The direction is **quiet, modern, native** — system materials, generous whitespace, one
accent, depth from soft shadow and hairline separators. Not negotiable:

- **Red means recording.** Nothing else in the app is red.
- **One accent** (indigo) for interaction. Speaker colours are instrumentation, never chrome.
- **Numbers are readouts**: `DS.Font.readout` + `.monospacedDigit()`, via the `Readout` view.
- **One of each**: `ToggleRow`, `PickerRow`, `InlineNotice` (`.info`/`.warning`),
  `EmptyState`, `PermissionRow`, `ModelRow`, `EngineRow`. Don't add a second toggle style.
- **Australian English** in every user-facing string (summarise, recognised, colour).
  Identifiers and persisted raw values stay as they are.
- **One word per thing**: note (never session/conversation/recording in copy), Record
  meeting / Stop, New note, "notes window" (not notepad), dictation bar, dictation(s),
  push-to-talk key, Transcription · Apple / Parakeet, Voice Notes account, Connected apps,
  Claude Desktop. Settings paths use `▸`.

Panels that float (dictation bar, the meeting offer, the notes rail) use a transparent
`NSHostingView` over a clear window; a SwiftUI `shadow` on a material capsule renders as a
rectangle, so they cast none.

---

## Meetings

`MeetingDetector` watches for two-way audio in known apps (`MeetingAppRegistry`) and shows
`OfferStrip`; `MeetingController` owns capture (mic + a Core Audio process tap for the call
side), the live transcript, bullets and the save path; `MeetingSummaryService` writes the
note with Apple Intelligence, in parts for long meetings. The notes window is
`NotepadWindow`, a full-height rail down the right edge. Calendar naming is read-only
through EventKit or the hosted Google connection. Speaker separation is optional and only
when its model is on disk.

## Cloud

`CloudAccount` (OAuth PKCE through `ASWebAuthenticationSession`, refresh token in the
Keychain, bootstrap from `<site>/api/config`) and `CloudSync` (versioned documents,
per-account sync index, conflict copies titled "(copy from this Mac)"). The origin comes
from `VoiceNotesSiteURL` in Info.plist. `docs/CLOUD.md` is the contract;
`docs/SELF-HOSTING.md` the deployment. The web app is Next.js on Vercel with Supabase; the
access-token hook binds third-party OAuth tokens to the MCP audience stored in
`murmur_config`.

## MCP

Two servers. Local: `murmur-mcp` inside the bundle, stdio, what Claude Desktop runs;
`ClaudeDesktopIntegration` merges it into `claude_desktop_config.json` with a backup and
can expose the snippet for other clients; `--allow-writes` enables `save_summary` with a
revision check. Remote: `<site>/mcp`, OAuth, read-only. `Tools/smoke-mcp.py` exercises the
local one.

## The developer switch

`defaults write com.jasonhunt.murmur developerMode -bool true`. Read once at launch, no UI.
Gates the benchmark lab: Engine comparison window, Compare mode (records every engine, types
nothing — forced off when the switch is off), `WisprReader`, the HTML dashboard, engine
chips and timings on dictation rows. Timings aren't comparable across engines: local ones
start the clock after model load; Wispr's is end-to-end including network.

---

## What isn't built

1. **Command Mode** — select text, hold a second key, "make this more formal." Needs an AX
   read of `kAXSelectedTextAttribute` plus an LLM round-trip.
2. **Notarisation** — needs the Apple Developer Program. Releases are signed (Apple
   Development) and users click Open Anyway once.
3. **Sparkle-style in-app updates** — the app checks GitHub Releases daily and links to the
   download; installing is drag-over.
