# Voice Notes

Voice Notes is the simple working name. Final branding is deferred. Existing bundle,
storage and infrastructure identifiers still use `murmur` so installed connections and
local data keep their established locations.

Dictation and meeting notes for macOS, with a private cloud library. Hold your shortcut, speak, and release to
insert cleaned-up text. During a meeting, capture your microphone and the call audio,
add your own notes, and turn the conversation into an editable summary.

Built in Swift 6 and SwiftUI, for macOS 26 on Apple silicon. No account or hosted service
is needed for recording, transcription, notes or on-device summaries. Speech and optional
speaker models may need an initial download. Apple Intelligence must be enabled for local
summaries. Sign in to sync finished meeting text to the web app. Text you ask a cloud AI client to read goes to that provider.

## Start

```bash
make install
```

This builds outside the repository, signs with a stable identity, installs in
`/Applications/Murmur.app`, and opens the app. Keep the running copy in Applications.
`make app` builds the bundle; `make run` installs and launches it; `make install LAUNCH=0`
installs without launching.

Grant Accessibility and Microphone during setup. For meetings, allow **system audio**
to capture the other side. Connect **Calendar** from the Meetings home screen to see
upcoming events and open scheduled links. Google Calendar can connect directly through the web app. Calendars already synced to your Mac also work through EventKit (System Settings → Internet Accounts).

## Everyday use

| Workflow | How it works |
|---|---|
| Dictate anywhere | Hold the configured modifier key and release to insert. The default is fn; existing shortcut preferences are preserved. The overlay keeps focus in your original app. |
| Review dictations | Dictation shows your history, word count and search. Compare mode clearly explains why it produces comparisons without inserting text. |
| Adjust the floating bar | Settings → Dictation lets you show or hide live words, choose the top, bottom, left or right screen edge, and preview without recording. The shadow-free bar sits close to the edge. |
| Check your account | Settings → Account on Mac and Settings on the web show your signed-in email, Google Calendar account and connection controls. Account identity is also visible in both sidebars. |
| Record a meeting | Choose **Record meeting** or press **⌘⇧R**. The floating notepad shows separate **You / Call** meters and timestamped personal notes. Stop saves the meeting to the library. |
| Capture calls automatically | A sustained call in a recognized app can start notes. Explicit per-app Ask, Auto and Never rules take priority. Manual recordings do not stop when another app releases its microphone. Muting alone does not end a recording. |
| Open scheduled meetings | Supported links open a minute before the event. **Google Meet opens in Chrome.** Enter the call yourself; Voice Notes starts capture when call audio is detected. Up next lets you join early or skip automatic opening. Past events and handled occurrences are not replayed. |
| Work with notes | Create a personal note with **⌘N**, search across titles, people, summaries, personal notes and transcripts, and pin the notes you return to. |
| Summarize | Use Meeting, 1:1, Stand-up or Interview templates. Apple Intelligence reads long meetings in parts and creates a separate Markdown note. Generation can be cancelled; existing notes remain intact. |
| Check the source | Notes have clickable timestamps, a searchable transcript and speaker filters. Speaker labels can be renamed. |
| Edit and export | Notes autosave. Check off actions, copy a meeting for AI, export Markdown, or restore a previous note version. Conflicting editor drafts survive navigation and relaunch. Deleted sessions go to the Mac's Trash. |

Automatic capture is local: Voice Notes does not send a bot, click a meeting's Join button,
or attend while the Mac is asleep. Keep Voice Notes running and your Mac awake. Browser
recognition uses audio activity and accessible window titles, with calendar context.
Opening a link alone does not trigger capture. Overlapping scheduled meetings ask you
to choose one in Up next.

System audio uses a system-wide output tap, so other sounds played during a recording
can be transcribed too. Headphones help keep call audio out of your microphone. Optional
speaker separation labels the call side as Speaker 1, Speaker 2, and so on; the first
moments may remain unlabelled while its models warm up. Speaker identity is not inferred
from your calendar's attendee list.

## Cloud library and connections

The hosted companion is [Voice Notes on the web](https://murmur-rho-pied.vercel.app). See
[deployment status and setup](docs/DEPLOYMENT.md) for the remaining account configuration.

In the Mac app, open **Settings → Account → Sign in to Voice Notes** (also available in Connections). The sign-in window uses OAuth
with PKCE; credentials are stored in the macOS Keychain. Completed sessions sync when
online. Recording, dictation and local editing continue without a connection.

The remote MCP URL is:

```text
https://murmur-rho-pied.vercel.app/mcp
```

Add this URL as a custom connector in ChatGPT or Claude, choose OAuth, and approve the
Voice Notes consent screen. Connected AI apps can read your synced notes and upcoming meetings
while the Mac is asleep. Access can be revoked in the web app’s Connections page.

The web app provides a searchable library, Markdown editing with recovery drafts, exports,
a Google Calendar agenda and connection management. Changes are checked against the server
version. If both the Mac and web copies changed, the Mac keeps an **offline copy** before
accepting the cloud version. Recordings and private editor drafts are never uploaded.

Deleting a note on your Mac does not delete its cloud copy. The local sync index remembers
the removal so it does not immediately download it again. Restoring a local note resumes
sync. Signing out keeps the local library. A library already bound to one account will not
silently upload into a different account.

| Remote MCP tool | What it reads |
|---|---|
| `list_sessions` | Your meetings and notes, with date filters and pagination. |
| `get_session` | The current written note, metadata and timestamped bullets. |
| `get_transcript` | A page of source segments; follow `nextOffset` through the whole meeting. |
| `search` / `fetch` | Search across notes and transcripts, then retrieve a linked source. |
| `list_upcoming_meetings` | Your connected Google Calendar agenda and its last sync time. |

The remote server uses Streamable HTTP and OAuth resource discovery. It validates the
issuer, signature and MCP-specific audience. Third-party OAuth clients cannot write to
the database. Supabase row-level policies separate each account’s library.

### Local connections

**Advanced → connect directly to this Mac** retains the standalone Claude Desktop
integration. It merges the configuration with a backup, supports opt-in summary writes
with revision checks, and requires the Mac to be running. Other local MCP clients use:

```json
{
  "mcpServers": {
    "murmur": {
      "command": "/Applications/Murmur.app/Contents/MacOS/murmur-mcp",
      "args": []
    }
  }
}
```

Add `"--allow-writes"` to expose `save_summary`. Each write needs the `note_version` read
from `get_session`. The local server also provides Markdown resources and summary prompts.
It never records audio or runs shell commands. `MURMUR_SESSIONS_DIR` selects another library.

## Your files

Sessions are ordinary local files under `~/Library/Application Support/Murmur/sessions`:

```text
<session-id>/
  session.json          title, dates, attendees, capture state, pin and note provenance
  transcript.jsonl      timestamped speech, flushed as final segments arrive
  notes.json            your timestamped notes during the meeting
  note.md               current editable note
  note.1.md, note.2.md   previous versions
  editing-draft.json    recoverable unfinished edit, when needed
```

No audio recordings are retained. Interrupted sessions recover the text already written.
A failed final save remains visible with **Retry save**. Quitting during capture waits for
saving. Editor drafts are private to the editor and are excluded from exports and MCP.
Writers share a cross-process file lock; notes are atomically replaced. Time Machine can
back up this directory normally.

Generated summaries can make mistakes; source notes and transcripts are retained for
review. Very large meetings that cannot be reduced within the local model's context
window show an error with a Copy for AI path instead of silently summarizing only a prefix.

## Development and checks

```bash
make test
MURMUR_MODEL_SMOKE=1 make test  # additionally runs a synthetic meeting through Apple Intelligence
python3 Tools/smoke-mcp.py     # checks the installed executable against temporary synthetic notes
python3 Tools/preview-fixtures.py
cd web && npm ci && npm run check && npm test && npm run build
npm run test:integration      # Docker + Supabase CLI; isolated local OAuth/database tests
```

`preview-fixtures.py` creates a separate sample library and prints its path. After installing a
debug build without launching, use the launch command in that script's header. Preview
mode disables hotkeys, calendar monitoring and automatic capture; manual recording remains
available for testing. Preview notes never enter the normal library.

`shared/dictionary-test-vectors.json` is the correction specification. Change it first
when changing correction behavior, copy it to `Tests/MurmurDictionaryTests/`, and run
`make test`. Correction semantics were not changed by the meeting-notes upgrade.

The key modules are `Murmur` (native app), `MurmurSessions` (files, notes and automation
policies and sync documents), `web/` (Next.js, OAuth, remote MCP and Calendar), `MurmurMCPServer` (local protocol handlers), `MurmurMCP` (stdio executable), and
`MurmurDictionary` (corrections). UI values belong in `UI/DesignSystem.swift`: quiet native
materials, one indigo accent, red for recording, and monospaced readouts for numbers.

Code signing is required for stable macOS permissions. The Makefile prefers Developer ID,
then Apple Development, before falling back to ad-hoc signing. Do not replace a stable
identity with `--sign -`. If Accessibility becomes wedged, reset only this app's row:

```bash
tccutil reset Accessibility com.jasonhunt.murmur
```

Quit System Settings before reopening its Privacy pane. Never reset all apps' permissions.

Command Mode and notarized distribution are still future work. The current upgrade has
been tested with synthetic notes and local capture; a real Google Meet with another
participant is still needed to validate your end-to-end audio setup.

Earlier naming concepts are parked. The [identity notes](docs/IDENTITY.md) retain the
competitive research; [Voice Notes](docs/identity/index.html) is the current working name.

## Credit

Forked from [per-simmons/murmur-youtube](https://github.com/per-simmons/murmur-youtube)
and adapted for daily use. Optional Parakeet transcription and speaker separation use
[FluidAudio](https://github.com/FluidInference/FluidAudio).
