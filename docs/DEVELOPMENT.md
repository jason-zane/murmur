# Developing Voice Notes

## Toolchain

- macOS 26 on Apple silicon; Xcode 26 (Swift 6.2 or newer). No Xcode project — this is a
  SwiftPM package driven by `make`.
- Python 3 for the smoke tests and preview fixtures.
- Node 24 only if you work on `web/` (the optional hosted backend).

```bash
make doctor        # checks all of the above and the signing identity, and says what to fix
```

## Targets

| Command | What it does |
|---|---|
| `make build` | `swift build` into `~/Library/Caches/MurmurBuild/scratch` (never inside the checkout) |
| `make test` | The whole suite. Slow (~20 min) because of the timeout tests; `TEST_ARGS='--filter CloudSyncWorkflowTests'` narrows it |
| `make app` | Assembles and signs `~/Library/Caches/MurmurBuild/Murmur.app`, stamping the version and site URL |
| `make install` | Copies it to `/Applications` and relaunches (`LAUNCH=0` to skip the launch) |
| `make release` | `make app` with `CONFIG=release` |
| `make dist` | Release build, `codesign --verify`, and a disk image in `dist/` (`ZIP=1` for a zip) |
| `make models` | Pre-downloads the optional on-device models from a terminal |
| `make clean` | Removes every build product, staged bundle and `dist/` |

Variables: `VERSION` (default: the git tag, or the short hash), `BUILD_NUMBER` (commit
count), `SITE_URL` (the hosted backend the app signs in to; see
[SELF-HOSTING.md](SELF-HOSTING.md)), `CONFIG` (`debug` or `release`).

Build products and the staged bundle live outside the tree on purpose: a checkout under a
file-provider-synced folder (Desktop, Documents, iCloud Drive) gets its files mutated and
xattr-stamped while the compiler and codesign are using them.

## Code signing and permissions

macOS keys the Accessibility grant to the code *signature*, not the path. An ad-hoc
signature changes on every build, so a rebuilt binary stops satisfying the stored grant —
and the symptom lies: the toggle in System Settings still shows **on**.

The Makefile therefore signs with the most stable identity it can find: **Developer ID
Application**, then **Apple Development** (free with an Apple ID in Xcode ▸ Settings ▸
Accounts — not distributable, but stable across rebuilds, which is what matters), then
ad-hoc. Don't replace that with `--sign -`.

Wedged grant? Reset only this app's row, then quit System Settings (⌘Q) before reopening:

```bash
tccutil reset Accessibility com.jasonhunt.murmur
```

Keep the bundle identifier `com.jasonhunt.murmur`, the executable name `Murmur`, the
`murmur://` URL scheme, the Keychain service and the entitlements as they are: every one of
them is part of an identity macOS has already granted on installed copies.

## Running from the build directory

Don't. `make install` puts the running copy in `/Applications`, which is where the login
item (`SMAppService` registers the bundle at its current path) and the Claude Desktop
connection (`…/Murmur.app/Contents/MacOS/murmur-mcp`) point. Onboarding shows a warning
when the app runs from anywhere else.

## Previewing the UI without your own notes

```bash
python3 Tools/preview-fixtures.py        # prints a synthetic sessions directory
open -n --env MURMUR_UI_TESTING=1 --env MURMUR_SESSIONS_DIR=<that path> \
     ~/Library/Caches/MurmurBuild/Murmur.app
```

Preview mode (debug builds only) skips the hotkey, cloud, calendar and call detection, and
reads notes from the given directory. `MURMUR_PREVIEW_OPEN` raises a screen on launch so a
screenshot needs no clicking: `settings`, `settings:meetings` (any tab, lower-cased),
`onboarding`, or `session:<id>`.

## Checks before a change ships

```bash
make build && make test
make app && python3 Tools/smoke-mcp.py ~/Library/Caches/MurmurBuild/Murmur.app/Contents/MacOS/murmur-mcp
MURMUR_MODEL_SMOKE=1 make test           # also runs a synthetic meeting through Apple Intelligence
```

`shared/dictionary-test-vectors.json` is the specification for text corrections. Change it
first, copy it to `Tests/MurmurDictionaryTests/`, and make the tests green; CI fails if the
two copies drift.

## The developer switch

The benchmark tooling — Engine comparison window, Compare mode (records every engine at
once and types nothing), the Wispr Flow database reader, and an HTML dashboard rewritten
after every dictation — is hidden behind one switch:

```bash
defaults write com.jasonhunt.murmur developerMode -bool true    # then relaunch
```

With it on, the menu bar gains **Developer ▸**, ⌘D opens the comparison window,
`murmur://show` and `murmur://clear` work, and dictation rows show the engine and timing.
With it off none of that exists, and Compare mode is forced off so nobody silently loses
dictation. The timing column doesn't compare like with like: Apple and Parakeet are timed
on local compute after model load; a Wispr row is its own end-to-end latency including the
network.

## Layout of the code

| Module | Contents |
|---|---|
| `Sources/Murmur` | The app. `Core/` dictation (hotkey, injection), `Meetings/` capture, detection and summaries, `Cloud/` account and sync, `UI/` SwiftUI with `DesignSystem.swift` as the only source of colours, sizes and timings, `Support/` settings, permissions, logging |
| `Sources/MurmurSessions` | The on-disk note library and sync documents, shared with the MCP server |
| `Sources/MurmurMCPServer`, `Sources/MurmurMCP` | The local MCP server Claude Desktop talks to, and its stdio executable |
| `Sources/MurmurDictionary` | Corrections and the vector tests |
| `web/` | The optional hosted backend (Next.js on Vercel, Supabase). See [CLOUD.md](CLOUD.md) and [SELF-HOSTING.md](SELF-HOSTING.md) |

Views must not contain literal values; if a component needs a number that isn't a token,
add the token. Red means recording and nothing else; one indigo accent; numbers are
readouts (`DS.Font.readout` + `.monospacedDigit()`, via `Readout`). User-facing copy is
Australian English.

## Working on the web app

```bash
cd web && npm ci && cp .env.example .env.local   # fill it in
npm run dev
npm run check && npm test && npm run build
npm run test:integration                         # Docker + Supabase CLI; isolated local stack
```

The integration runner starts a separate local Supabase stack on ports 5632x, applies the
migrations, runs every rollback fixture in `supabase/tests/`, the OAuth/database tests with
real tokens and the booking flow against an in-memory Google Calendar, and leaves the stack up; `supabase stop` from the repository root stops it.
Version conflicts use PostgreSQL error `PT409` (HTTP 409 from PostgREST, no retry); don't
use `40001`, which means a serialisation failure and can trigger automatic retries.

## Releasing

1. Tag: `git tag v0.6.0 && git push origin v0.6.0`.
2. `.github/workflows/release.yml` builds `make dist` on a macOS runner and publishes the
   disk image to a GitHub release. With `SIGNING_CERTIFICATE_P12` (base64 of the exported
   Apple Development certificate and key) and `SIGNING_CERTIFICATE_PASSWORD` set as
   repository secrets, it signs with that identity — the same one every time, so users'
   Accessibility grants survive updates. Without them the release is ad-hoc signed and the
   notes say so.
3. The app's update check (`Support/UpdateCheck.swift`) compares the release tag with the
   bundle version once a day. Development builds carry a git hash as their version and
   never report an update.

Notarisation is deliberately not part of this: it needs the Apple Developer Program.
[INSTALL.md](INSTALL.md) tells people how to open an un-notarised app.
