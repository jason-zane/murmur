# Working on this repo

Read this before changing anything. It is written for a coding agent picking the project up
cold, and it is mostly a list of things that look wrong but aren't, plus things that look
fine and will bite you.

---

## What this is

Push-to-talk dictation for macOS. Hold **fn**, talk, release, and cleaned-up text is typed
into whatever had focus. Swift 6, SwiftUI, no sandbox, everything on-device.

It replaces a Wispr Flow subscription, so "as good as Wispr for daily use" is the bar —
not "a demo that transcribes."

A Windows port existed upstream and has been removed. If you find a reference to C#,
Avalonia, sherpa-onnx or `windows/`, it is a leftover — delete it.

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

**Compare mode doesn't type anything.** By design — `Settings.compareMode` runs every
engine on one recording and shows them side by side. If both injected, two transcripts
would fight over one text field. This is the single most confusing behaviour in the app.

**The timing column isn't comparing like with like.** Apple and Parakeet are timed on local
compute with the clock started *after* model load. Any Wispr row read from its database is
its own `e2eLatency`, which includes a network round trip and its cleanup pass. Don't
present them as one ranking.

**`MainActor.assumeIsolated` will crash the process.** It does not check the claim, it
asserts it. Use `await MainActor.run` from any non-main-actor context. This took the app
down once already.

**Mutating `@State` inside a `Canvas` draw closure floods the log and corrupts state.** The
VU meter keeps its needle physics in a plain reference type the view merely holds, which is
invisible to SwiftUI's state graph. Don't "clean that up" into `@State`.

**`TextInjector` ignores the AX return value on purpose.** Electron apps, Chrome and most
terminals return `.success` from the `kAXSelectedTextAttribute` write and then silently
drop it. The AX path is only trusted when the caret can be observed to have moved.

**fn is not consumed by the event tap.** Swallowing it would break fn+arrow, fn+delete and
the emoji picker. Right ⌥ and Right ⌘ *are* consumed, because they have no other job.

---

## Code signing is load-bearing, not cosmetic

TCC stores a code-signing *requirement* per entry, not just a path. An ad-hoc signature
changes every build, so the rebuilt binary stops satisfying the stored requirement — and
the symptom lies: the Accessibility toggle still shows as **on** while the app is
untrusted.

The `Makefile` resolves an identity in this order: **Developer ID Application** →
**Apple Development** → ad-hoc. This machine has only the Apple Development cert, which is
not distributable but *is* stable across rebuilds — which is the property TCC cares about.
**Don't replace that with `--sign -`.**

If a grant does get wedged, reset that one row — never toggle, and never omit the bundle ID:

```bash
tccutil reset Accessibility com.jasonhunt.murmur
```

A bare `tccutil reset Accessibility` wipes every app on the machine. Then quit System
Settings entirely (⌘Q) before reopening; the Privacy pane caches its list.

---

## Build notes

**Always build with `make`.** It uses `--scratch-path` outside the source tree. A bare
`swift build` writes `.build/` into the repo.

**Never copy a scratch directory between paths.** The precompiled module cache has its
absolute path baked in, and the build fails with "was compiled with module cache path …
but the path is currently …". Delete and rebuild instead.

**`log` may be shadowed in the user's shell.** Use `/usr/bin/log` explicitly:

```bash
/usr/bin/log show --predicate 'subsystem == "com.jasonhunt.murmur"' --last 5m
```

**Don't run the `.app` out of the build directory.** `make install` puts the running copy
in `/Applications`, which is also where the login item needs it to be — `SMAppService`
registers the bundle at its current path, so registering a staged copy would pin the login
item to a build artifact.

---

## Design system

`Sources/Murmur/UI/DesignSystem.swift` defines every colour, size, radius, duration and
material token. **Views must not contain literal values.** If a component needs a number
that isn't a token, add the token rather than inlining it.

The direction is 1980s field recorders — Sony TC-D5, Marantz PMD, Nakamichi, Braun. Silver
face in light appearance, black face in dark. Two rules that are not negotiable:

- **Red means recording.** Nothing else in the app is red.
- **Amber and green are instrumentation only** — level meters, never UI chrome.

Explicitly ruled out: neon, vaporwave, synthwave, purple/pink gradients, glowing text,
chrome lettering, grid horizons. There are **no gradients anywhere**; depth comes from flat
panels, hairline bevels and procedurally-drawn brushed grain.

---

## Regex, if you touch the dictionary

**NFC normalization is required.** macOS returns decomposed strings, so without it an
accented trigger silently never fires.

Stay inside the safe subset — `\b`, `\d`, `\w`, `\s`, character classes, greedy/lazy
quantifiers, alternation, `(?<name>…)`, fixed-length lookbehind, lookahead, `\p{L}`, and
`$1`–`$9` in replacements. Nothing else.

---

## What isn't built

1. **Command Mode** — select text, hold a second key, "make this more formal." Needs an AX
   read of `kAXSelectedTextAttribute` plus an LLM round-trip.
2. **Onboarding** — a first-run window walking through the two permissions.
3. **Notarization** — only needed to distribute; irrelevant for personal use.
