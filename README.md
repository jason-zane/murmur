# Voice Notes

Dictation and meeting notes for the Mac. Hold a key and speak — the words land wherever
your cursor is. When a call starts, Voice Notes can record both sides, keep your own notes
beside it, and turn the whole thing into a summary on the Mac itself. Nothing leaves the
machine unless you sign in.

macOS 26 on Apple silicon. Apple Intelligence for summaries and smart cleanup.

## Install

1. Download the latest `VoiceNotes-<version>.dmg` from
   [Releases](https://github.com/jason-zane/murmur/releases/latest).
2. Drag **Voice Notes** to **Applications**.
3. First open: right-click ▸ **Open**. If macOS blocks it, go to **System Settings ▸ Privacy
   & Security** and click **Open Anyway**. The app is signed but not notarised — that needs
   a paid Apple account this project doesn't have.

[docs/INSTALL.md](docs/INSTALL.md) has every step, the permissions, and what to do if one
gets stuck.

## First run

The app asks for **Accessibility** and **Microphone** (dictation), then **Audio recording**
and **Calendars** (meetings, optional). Each row shows what macOS actually reports, so you
can see when a grant has taken. Turn on Apple Intelligence in System Settings if you want
summaries.

## Dictate

Hold **Right ⌥** in any text field, speak, release. Live words appear in a small bar at the
edge of the screen; the finished text is typed where you were. Change the key, the
activation style (hold, tap to toggle, or both), the engine and the cleanup in
**Settings ▸ Dictation**. Names and jargon it keeps getting wrong go in **Settings ▸
Dictionary**. Your dictations stay in the app's **Dictation** list.

Two engines: **Apple** streams text as you speak and needs no download; **Parakeet** is more
accurate on English, produces text when you release, and is a ~470 MB download offered
right where you choose it.

## Record a meeting

When a call starts in Google Meet, Zoom, Teams and other apps, a small offer appears at the
top of the screen. **Record** opens a narrow notes window down the right edge where you can
type while the meeting runs, with one line telling you both sides are being heard. Or
start yourself: menu bar ▸ **Record meeting** (⌘⇧R).

Stop, and the meeting is in your library with a timestamped transcript. **Summarise**
writes the note with Apple Intelligence — Meeting, 1:1, Stand-up or Interview templates —
and you can edit it, copy it for another AI, export Markdown, or restore an earlier version.
Speakers on the call side can be told apart (optional model) and renamed.

Per-app rules (always ask, always record, never) and the calendar behaviour are in
**Settings ▸ Meetings**. Voice Notes doesn't join calls or send a bot; it listens to what
your Mac plays, so keep it running and the Mac awake.

## Connect Claude Desktop

**Settings ▸ Connections ▸ Connect Claude Desktop** lets Claude read your notes on this Mac
— ask about last week's decisions, or have a note summarised — with nothing leaving the
machine. It runs while Voice Notes is running. Any other MCP app can use the same command;
the configuration to paste is under *Using another app*:

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

Add `"--allow-writes"` to let the app save summaries into your notes.

## Optional: an account

Signing in (**Settings ▸ Connections**) puts your finished notes on the web, connects Google
Calendar, and gives you a connector URL for ChatGPT or Claude so they can read your notes
from anywhere, even while the Mac is asleep. Recordings are never uploaded; recording and
editing keep working offline. If a note changes in both places, both versions are kept.

The reference deployment is [murmur-rho-pied.vercel.app](https://murmur-rho-pied.vercel.app):
anyone with the link can create an account, reset a password, or delete the account and
everything in it. To run your own backend, see [docs/SELF-HOSTING.md](docs/SELF-HOSTING.md);
[docs/CLOUD.md](docs/CLOUD.md) explains the trust model.

## Where your files are

Notes are ordinary files under `~/Library/Application Support/Murmur/sessions`:

```text
<session-id>/
  session.json          title, dates, attendees, capture state, pin and note provenance
  transcript.jsonl      timestamped speech
  notes.json            your timestamped notes during the meeting
  note.md               the current note; note.1.md, note.2.md… earlier versions
```

No audio is kept. The dictionary is `dictionary.txt` beside them; downloaded models live in
`~/Library/Application Support/FluidAudio`. Time Machine backs all of it up normally.

## Build from source

```bash
make doctor      # toolchain and signing check
make install     # build, sign, install to /Applications, launch
```

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers the targets, signing, previews, tests
and releases.

## Credit

Forked from [per-simmons/murmur-youtube](https://github.com/per-simmons/murmur-youtube)
and adapted for daily use. Optional Parakeet transcription and speaker separation use
[FluidAudio](https://github.com/FluidInference/FluidAudio).
