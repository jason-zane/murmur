# Murmur

Push-to-talk dictation for macOS. Hold **fn**, talk, release — cleaned-up text lands in
whatever text field has focus. Everything runs on this Mac; no account, no subscription,
no audio leaves the machine.

A Wispr Flow replacement, built native.

---

## Quick start

```bash
make install     # builds, bundles, signs, copies to /Applications, launches
```

Then grant two permissions — neither is optional, and neither can be requested silently:

| Permission | Where | Needed for |
|---|---|---|
| **Accessibility** | System Settings ▸ Privacy & Security ▸ Accessibility | The `CGEventTap` that sees the hotkey, and the AX text insert |
| **Microphone** | Prompted on first dictation | Audio capture |

Restart Murmur after granting Accessibility, then hold **fn** and talk.

Other targets: `make app` (bundle only), `make run` (run in place), `make clean`.

---

## How it behaves

- **Hold fn** anywhere to dictate. fn is deliberately *not* swallowed, so fn+arrow,
  fn+delete and the emoji picker keep working. Switch to Right ⌥ or Right ⌘ in Settings
  if anything fights over it.
- **Cleanup is on.** Fillers stripped, punctuation restored, paragraphs formed. With
  *Smart cleanup* enabled it uses Apple's on-device LLM, which also honours spoken
  corrections like "make that three, actually" — and falls back to the deterministic
  rule pass if the model stalls or isn't available.
- **The dictionary** teaches it names and jargon two ways: it biases the engine *before*
  transcribing, then runs a guaranteed correction pass *after*. Corrections catch glued
  forms too, so "Claude Code" also fixes "CloudCode" and "Cloud-Code" without ever
  touching "Cloudflare".
- **Starts at login**, so the hotkey is always armed.

---

## Signing, and why it matters here

TCC stores a code-signing *requirement* per entry, not just a path. An ad-hoc signature
changes on every build, so a rebuilt binary stops satisfying the stored requirement — and
the symptom lies: the Accessibility toggle still shows **on** while the app is reported
untrusted, and flipping it changes nothing, because the stale row is the problem.

The `Makefile` therefore signs with a stable identity, preferring a Developer ID and
falling back to the **Apple Development** cert on this machine. Both are stable across
rebuilds, which is the property that actually matters.

If a grant ever does get wedged, reset that one row and re-add — never toggle:

```bash
tccutil reset Accessibility com.jasonhunt.murmur
tccutil reset Microphone   com.jasonhunt.murmur
```

Always pass the bundle ID. A bare `tccutil reset Accessibility` wipes **every** app on the
machine. Then quit System Settings entirely (⌘Q) before reopening — that pane caches its
list and will otherwise show the row you just deleted.

---

## Architecture

```
 hold fn ─► HotkeyMonitor ──► DictationController ◄── Settings
                                │
                     ┌──────────┼──────────┐
                     ▼          ▼          ▼
              AudioCapture  HUDPanel   TranscriptionEngine
                     │                      │
                (AudioChunk) ──ordered──► Apple SpeechAnalyzer
                                          or Parakeet (FluidAudio)
                                            │
                                       (transcript)
                                            ▼
                                    Dictionary corrections
                                            ▼
                                    TextFormatter (rules or on-device LLM)
                                            ▼
                                      TextInjector ─► focused app
```

### Decisions worth knowing

**The HUD must never take focus.** `HUDPanel` is a `.nonactivatingPanel` with
`canBecomeKey == false`. This is the load-bearing detail of the whole app: if the overlay
took key status, the user's text field would lose focus and there'd be nothing left to
inject into.

**The hotkey needs a `CGEventTap`, not `NSEvent`.** `fn` and left/right modifier
discrimination don't surface through `NSEvent.addGlobalMonitorForEvents` or the Carbon
hotkey API — which is why Accessibility is a hard requirement rather than a nicety.

**Injection can't trust its own return value.** Electron apps (Cursor, VS Code, Slack),
Chrome and most terminals report `kAXSelectedTextAttribute` as settable, accept the write,
and silently drop it. So the AX path is only trusted when the insertion point can be
*observed* to have moved; otherwise it falls back to pasteboard + ⌘V and restores the
previous pasteboard.

**Audio ordering is explicit.** `AudioCapture` yields into an `AsyncStream` drained by a
single task. Spawning a `Task` per buffer would be simpler and would silently corrupt the
transcript, because unstructured tasks have no ordering guarantee.

**Two swappable seams.** `TranscriptionEngine` and `TextFormatter` are protocols so the
two components most likely to change can change without touching anything else.

### Layout

```
Sources/
├── MurmurDictionary/            correction engine (own target, unit-tested)
└── Murmur/
    ├── MurmurApp.swift          @main, AppDelegate, MenuBarExtra
    ├── Core/                    hotkey, audio, injection, controller
    ├── Transcription/           engine protocol, Apple, Parakeet
    ├── Formatting/              rule-based + on-device LLM cleanup
    ├── Dictionary/              persistence
    ├── UI/                      main window, HUD, settings, dictionary panel
    └── Support/                 settings, permissions, login item, logging
```

---

## Speech engines

Default is Apple's **`SpeechAnalyzer` / `SpeechTranscriber`**: no dependency, no bundled
model, no cloud path, and real streaming so text appears while you're still talking.

**Parakeet v3** via FluidAudio (CoreML on the Neural Engine) is the alternative — better
English accuracy, ~100× realtime, but batch rather than streaming, so no live text in the
HUD. Download it from the menu bar item when the Parakeet engine is selected.

*Compare mode* runs both on one recording and shows them side by side. It deliberately
injects nothing — two transcripts would fight over one text field.

---

## Design

`Sources/Murmur/UI/DesignSystem.swift` defines every colour, size, radius, duration and
material token. Views must not contain literal values.

The direction is quiet, modern, native: the app should look like it belongs on macOS in 2026.
System materials, generous whitespace, one accent, and depth from soft shadow and hairline
separators rather than bevels or ornament. Three rules keep it coherent:

- **One accent.** Indigo carries interaction — selection, focus, the live waveform. **Red
  means recording and nothing else** is red.
- **Semantic colours where macOS provides them.** `.primary`, `separatorColor` and the material
  backgrounds adapt to appearance, accent tint and increased contrast for free.
- **Motion is spring, not linear.** Interface elements have mass; nothing cuts.

Two amendments for meetings, both documented in the token file:

- **Speaker colours are instrumentation.** A four-value scale labels who is talking and
  appears nowhere else. You are always the accent; nobody is ever red.
- **Every number is a readout.** Durations, timestamps, counts and confidences are tabular
  monospace, always. The twin *You / Call* meter is the recognisable mark of the meeting
  side — it appears wherever audio is live, because it is the proof that both streams are
  being heard.

## Not built

1. **Command Mode** — select text, hold a second key, "make this more formal."
2. **Onboarding** — a first-run window walking through the two permissions.
3. **Notarization** — fine for personal use; needed only to distribute.

---

## Credit

Forked from [per-simmons/murmur-youtube](https://github.com/per-simmons/murmur-youtube),
then reduced to the macOS app and adapted for daily use.
