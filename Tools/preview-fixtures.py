#!/usr/bin/env python3
"""Create a separate, synthetic library for native UI review. Never reads user notes.

After `make install LAUNCH=0`, launch the installed debug app with:
open -n --env MURMUR_UI_TESTING=1 --env MURMUR_SESSIONS_DIR=<printed path> /Applications/Murmur.app
Hotkeys, automatic capture and calendar monitoring are inactive in preview mode.
"""
import datetime as dt
import json
from pathlib import Path
import tempfile
import uuid

root = Path(tempfile.mkdtemp(prefix="murmur-preview-")) / "sessions"
root.mkdir()
now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)

def session(identifier, title, age, duration, transcript, note, pinned=False, personal=False):
    folder = root / identifier
    folder.mkdir()
    start = now - dt.timedelta(hours=age)
    manifest = dict(id=identifier, title=title, startedAt=start.isoformat(),
                    endedAt=(start + dt.timedelta(seconds=duration)).isoformat(),
                    state="noted", app=None if personal else "Google Meet",
                    bundleID=None if personal else "com.google.Chrome",
                    attendees=[] if personal else [{"name": "Maya Chen"}, {"name": "Sam Rivera"}],
                    speakers=[] if personal else ["You", "Maya", "Sam"],
                    engine="Notes" if personal else "Apple", segmentCount=len(transcript),
                    duration=duration, pinned=pinned, noteSource="Sample library", summaryTemplate="meeting")
    (folder / "session.json").write_text(json.dumps(manifest, indent=2))
    lines = [dict(id=str(uuid.uuid4()), start=t, end=t+8, source="you" if speaker == "You" else "call",
                  speaker=speaker, text=text) for t, speaker, text in transcript]
    (folder / "transcript.jsonl").write_text("".join(json.dumps(line)+"\n" for line in lines))
    bullets = [] if personal else [dict(id=str(uuid.uuid4()), at=156, text="Keep the pilot small. Agree on a clear support owner before Friday.")]
    (folder / "notes.json").write_text(json.dumps(bullets))
    (folder / "note.md").write_text(note)
    (folder / "note.1.md").write_text("## Initial notes\nA small pilot, with a Friday launch to confirm.\n")

session("sample-launch", "Pilot launch · final decisions", 1, 1472, [
    (0, "You", "Let's keep this focused on the pilot. What do we need before Friday?"),
    (35, "Maya", "The onboarding flow is ready. Five customers is the right size for the first group."),
    (156, "You", "Let's start with five customers and keep the feedback loop short."),
    (224, "Sam", "I can own support for the first week. I'll share a short handover on Thursday."),
    (382, "Maya", "We agreed to launch the pilot on Friday. I will send the checklist on Thursday."),
    (510, "You", "The budget stays at two thousand dollars. No change to the scope."),
    (728, "Sam", "How should we measure success after the first week?"),
    (903, "You", "Let's review activation and the feedback we get. We haven't set a target yet."),
    (1420, "Maya", "Great. Five customers, Friday launch. I'll follow up with the checklist tomorrow."),
], """## Summary
We're ready for a small, focused pilot on **Friday**. Start with five customers, keep the budget at **$2,000**, and use the first week to learn.

## Decisions
- Launch to five customers on Friday. [6:22]
- Keep the existing scope and $2,000 budget. [8:30]
- Sam will own support during the first week. [3:44]

## Action items
- [ ] Send the launch checklist — Maya (Thursday) [6:22]
- [ ] Share the support handover — Sam (Thursday) [3:44]

## Open questions
- What activation target should we use for the first week? [15:03]
""", pinned=True)

session("sample-weekly", "Product team · weekly sync", 4, 1830, [
    (0, "You", "Let's go through what shipped and what needs attention."),
    (120, "Maya", "The new onboarding flow is ready for review. I will book a walkthrough for Wednesday."),
], "## Summary\nThe team reviewed onboarding and agreed to a walkthrough on Wednesday.\n\n## Action items\n- [ ] Book the onboarding walkthrough — Maya (Wednesday) [2:00]\n")
session("sample-ideas", "A few ideas for next week", 27, 0, [], "## Things to explore\n- A calmer first five minutes for new customers.\n- Better prompts for feedback after the pilot.\n- A short weekly note on what we've learned.\n", personal=True)
print(root)
