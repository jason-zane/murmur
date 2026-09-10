# Installing Voice Notes

Voice Notes runs on macOS 26 (Tahoe) or later, on Apple silicon. It is a small download and
it keeps everything on your Mac unless you choose to sign in.

## 1. Download and open

1. Download `VoiceNotes-<version>.dmg` from the
   [latest release](https://github.com/jason-zane/murmur/releases/latest).
2. Open the disk image and drag **Voice Notes** onto the **Applications** shortcut beside it.
   It has to live in Applications: starting at login and the Claude Desktop connection both
   point at the app's location.
3. Eject the disk image and open Voice Notes from Applications.

### "Apple could not verify Voice Notes is free of malware"

Voice Notes is signed but **not notarised** — that needs a paid Apple developer account,
which this project doesn't have. macOS therefore blocks the first launch. Once, do this:

1. Open **System Settings ▸ Privacy & Security**.
2. Scroll to the *Security* section. A line says *"Voice Notes" was blocked to protect your
   Mac*. Click **Open Anyway** and confirm.

Or, from Terminal:

```bash
xattr -d com.apple.quarantine /Applications/Murmur.app
```

(The bundle is called `Murmur.app` on disk; that is the app's original name and changing
it would reset every permission you grant below.)

You only do this once. Updates installed the same way keep the approval.

## 2. Permissions

The first run walks you through four permissions. Each row shows what macOS actually
reports right now, so you can see when a grant has taken.

| Permission | Needed for | Required? |
|---|---|---|
| **Accessibility** | Seeing the key you hold, and inserting text where you're typing. | Yes — dictation doesn't work without it |
| **Microphone** | Your side of every dictation and call. | Yes |
| **Audio recording** | The other side of a call: the audio your Mac is playing. Separate from the microphone. | For meetings |
| **Calendars** | Naming meetings after the event and knowing who was there. Read-only. | Optional |

Accessibility can't be requested by an app — macOS opens System Settings and you switch
Voice Notes on there. If the switch is already **on** but Voice Notes still says it isn't
granted, the stored grant belongs to an older copy of the app. Don't toggle it. Reset that
one entry and add the app again:

```bash
tccutil reset Accessibility com.jasonhunt.murmur
```

Then quit System Settings completely (⌘Q) before reopening it; the Privacy pane caches its
list. The first-run window shows this fix automatically when it applies. Never run
`tccutil reset Accessibility` without the identifier — that resets every app on the Mac.

## 3. Apple Intelligence

Summaries and "smart cleanup" of dictated text use Apple Intelligence on your Mac. Turn it
on in **System Settings ▸ Apple Intelligence & Siri** if it isn't already. Without it,
dictation still works (with rule-based cleanup) and meetings are still transcribed; the
**Summarise** button explains why it's unavailable.

## 4. Optional: Parakeet

Apple's transcriber needs no download and shows words as you speak. **Parakeet** is more
accurate on English but only produces text when you release the key, and it is a ~470 MB
download. Choose it in **Settings ▸ Dictation** (or **Settings ▸ Meetings** for meetings);
the download button appears right there. Until it's downloaded, Apple is used.

## Everyday use

- **Dictate**: hold **Right ⌥** in any text field, speak, release. The key, the engine and
  cleanup are in Settings ▸ Dictation. Names and jargon it keeps getting wrong go in
  Settings ▸ Dictionary.
- **Meetings**: when a call starts in Meet, Zoom, Teams and others, a small offer appears at
  the top of the screen. **Record** opens a narrow notes window down the right edge of the
  screen where you can type as the meeting runs. Stop, and the meeting is in your library
  with a transcript; **Summarise** writes the note. Or start one yourself from the menu
  bar (⌘⇧R).
- **Claude Desktop**: Settings ▸ Connections ▸ **Connect Claude Desktop** lets Claude read
  your notes on this Mac. Quit and reopen Claude afterwards.

## Updating

Voice Notes checks the project's releases once a day (Settings ▸ General) and shows
**Update available** in the menu bar. Download the new disk image and drag it over the old
copy in Applications. Your permissions survive because every release is signed the same
way; your notes are never inside the app.

## Uninstalling

Drag Voice Notes out of Applications. Your notes are ordinary files you may want to keep:

```text
~/Library/Application Support/Murmur/          notes, transcripts, the dictionary
~/Library/Application Support/FluidAudio/      downloaded models (Parakeet, speaker separation)
```

Delete those to remove everything. If you connected Claude Desktop, remove the `murmur`
entry from `~/Library/Application Support/Claude/claude_desktop_config.json` (a backup of
the file from before Voice Notes touched it sits next to it). If you signed in, your
account can be deleted from the web app's Settings; that removes every synced note.
