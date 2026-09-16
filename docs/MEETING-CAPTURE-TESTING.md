# Meeting capture checks — 16 September 2026

This pass targets losing the far side of a call, preserving earlier words when something
fails, and making failures visible. It does not establish that every meeting app, headset,
or sleep/wake transition works.

## Automated failure tests

`Tests/MurmurAppTests/MeetingRecordingTests.swift` injects microphone, system-capture and
speech-engine substitutes. No personal audio or notes are used.

- Microphone permission denied: neither input starts and no empty note remains.
- Call capture cannot start: the microphone keeps working and the incomplete note is flagged.
- Delayed tap startup after Stop: late audio cannot enter the next note; the old tap stops.
- Pause/Resume: note identity, typed bullets and transcript timestamps survive the gap.
- Stop during Pause or Resume: previously received words are saved.
- Resume cannot obtain microphone access: the paused note remains available to save.
- Speech engine reports failure during capture or finalisation: a warning remains after saving.
- Speech event stream closes unexpectedly: capture no longer fails silently.
- Output route changes: capture reconnects, or the failed reconnect is reported while the mic continues.
- Saving is blocked: the transcript remains in memory and Retry save writes it successfully.
- Speech engine hangs: the real 20-second deadline permits earlier words to be saved.
- Pause times out and Resume succeeds: the possible earlier gap still produces a completion warning.
- No call-side speech: the completed note is flagged; a note containing both sources is not.

The first failure-injection run exposed ignored errors during finalisation, unreported
stream closure, and warnings disappearing after completion. These paths were repaired.
The main window now displays active capture warnings as well as save errors.

A broader run passed 58 tests across 11 suites, including dictation cancellation, browser
call detection, interrupted-note recovery, timestamp alignment, storage conflicts and MCP
access. Commands:

```sh
make test TEST_ARGS="--filter 'MeetingRecordingTests|DictationWorkflowTests|BrowserCallStateTests|MurmurSessionsTests|MCPServerTests'"
make test TEST_ARGS='--filter hungTranscriberCannotPreventSavingEarlierWords'
```

## Hardware diagnostics

Run the installed debug app after ending any active note and quitting Voice Notes:

```sh
/Applications/Murmur.app/Contents/MacOS/Murmur --diagnose-system-audio
/Applications/Murmur.app/Contents/MacOS/Murmur --diagnose-system-audio --exercise-restarts
/Applications/Murmur.app/Contents/MacOS/Murmur --diagnose-system-audio --browser-audio
```

The default diagnostic opens the microphone to exercise Bluetooth call mode and plays a
short system sound. The restart variant closes and reopens the microphone and restarts
call capture twice, reporting buffers and peak amplitude for each of three cycles.
The browser variant listens for 25 seconds and prints recognised call-side speech; use
known synthetic speech in Chrome. These commands create no note and save no audio.

The earlier Chrome check on the connected Sony WH-1000XM5 headset recognised both sentences
of the synthetic speech through the call-side transcriber. A real Teams call, other
headsets, unplug/replug, sleep/wake, and a long-duration call remain separate manual checks.

The three-cycle hardware check passed on 16 September with the WH-1000XM5 microphone
active. Each cycle received non-silent call audio:

| Cycle | Buffers | Frames | Peak amplitude |
| --- | ---: | ---: | ---: |
| Initial capture | 679 | 115,877 | 0.2203 |
| First restart | 697 | 118,949 | 0.2184 |
| Second restart | 686 | 117,072 | 0.2184 |

Both real-deadline timeout cases (Stop, and Pause followed by Resume) passed in a separate
40-second run after the final warning-retention change.
