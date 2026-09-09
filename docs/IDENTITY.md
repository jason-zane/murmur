# Voice Notes — working name

The user asked for a simple temporary name after rejecting Saybourne. The app uses
**Voice Notes** for its Mac and web labels. Final naming and branding are deferred.
The existing waveform symbol and interface remain the visual identity for now.

Bundle identity, executable, local storage, URL scheme, MCP identifiers and hosted origin
retain their existing `murmur` values. This is a display-name change, with no data or
authentication migration. The [public working-name page](https://murmur-rho-pied.vercel.app/identity.html)
replaces the earlier direction study; its source is `web/public/identity.html` and
the matching local copy is [here](identity/index.html).

The competitive findings and name explorations below are archived context. Dayriff,
Sayborne and Saybourne are not current proposals. No new availability claim is made for
the descriptive working name.

## Why move away from Murmur

[MurmurAI](https://murmurai.app/) advertises a closely overlapping Mac product: local
transcription, hotkey dictation, speaker editing, transcript chat, reusable refinement
prompts and file import. Its published capabilities are useful reference material; its
accuracy and day-to-day experience have not been tested in this project.

The naming problem is broader than one competitor. [Try Murmur](https://www.trymurmur.app/en)
also describes local Mac meeting transcription and summaries, while
[Murmur Notes](https://murmurnotes.com/) is a local Mac notes app with iCloud sync.
Adding “AI”, “Flow” or a spelling variation would leave the product in a crowded naming family.

## What to learn from MurmurAI

| Published capability | Application to our product |
| --- | --- |
| Editable speaker assignments | Extend our existing rename action to correct individual transcript segments, with undo. |
| Reusable custom prompts | Expand the existing summary templates with saved personal instructions, preserving source and version history. |
| Audio/video file import | Let the same library accept existing recordings, with explicit progress and cancellation. |
| Transcript chat with a chosen model | Complete the simple OAuth MCP connection first. Answers should cite the meeting and source timestamps. |
| Multiple transcription engines | Keep engine choice in settings; show the engine actually used and offer a clear fallback. |
| Export formats | Keep Markdown central for notes; add caption exports when file transcription is available. |

These are product directions, not claims that the outstanding features have shipped.

The defining experience should be a dependable personal tool: speak into any app, stay
present during a call, and find the resulting notes from the Mac, browser or chosen AI app.
Audio processing stays on the device. Account sync and access from other apps are explicit.

## Archived name directions

### Dayriff

Pronunciation: **day-riff**. Everyday speech and ideas, with “riff” suggesting thinking aloud.
It covers short dictation, conversations and personal notes without tying the product to
one speech model or meeting provider. Its musical association is the main tradeoff.

- Position: a little more room to think.
- Line: **Make something of what you say.**
- Wordmark: compact, rounded lowercase lettering.
- Symbol: a small looping monogram, built to work in the menu bar and Dock.
- Voice: warm, direct and lightly expressive. “Ready when you are.” “Saved on this Mac.”

### Sayborne

Pronunciation: **say-born**. Words carried into the rest of your day. It has a more editorial,
considered feel. It is less immediately familiar, and “borne” may need spelling aloud.

- Position and line: **Your words, carried forward.**
- Wordmark: a simple serif with a small folded-line symbol.
- Voice: measured, thoughtful and clear. “Stay in the moment. Keep what matters.”

## Initial name screen — 9 September 2026

Exact-name and category web searches did not surface a competing speech or notes product
called Dayriff or Sayborne. Apple's Mac App Store search API returned no exact-name matches.
Google Registry's RDAP endpoint returned HTTP 404 for both `dayriff.app` and `sayborne.app`.
These are preliminary findings: an absent registration record is not a purchase guarantee,
and web search is not trademark clearance. No domain has been bought or account renamed.

Sayborne also appears as a surname and in unrelated company references; Dayriff appears as
an existing online handle. The names are not asserted to be unused words.

Several plausible alternatives were removed after checking. For example,
[Saylet](https://play.google.com/store/apps/details?id=com.bffl.transcriber.speech.to.text.ai)
and [Saykeep](https://www.saykeep.app/) already describe closely related voice products.
[TellTide](https://telltide.com/) and [Tellune](https://tellune.app/) are existing software brands.

## Shared visual direction

Warm paper `#F5F2EB`, dark ink `#24243A`, indigo `#5049A6`, pale lilac `#E9E5F7`.
One interaction accent. Red remains exclusive to recording. Use native materials and
system typography in the Mac controls, with expressive typography in spacious welcome
and overview screens. The source transcript should remain easy to reach from the note.

The brand's character comes from its symbol, typography, copy and gentle transitions.
The recording controls should always be easy to read and predictable.

## Future adoption plan, when final branding resumes

1. Check the selected name against relevant trademark registers and domain registration.
2. Apply the display name, icon, wordmark, window copy and web metadata consistently.
3. Add the new hosted origin and OAuth redirects, update the MCP resource audience and
   refresh connection instructions as one coordinated deployment.
4. Preserve the existing signing requirement, library paths and Keychain access, with
   explicit migration where necessary. Avoid making existing permissions or notes disappear.
5. Verify the installed app, offline recovery, Google connection and ChatGPT/Claude OAuth
   flows under the chosen public identity.

The resource names created so far are provisional infrastructure names. They do not
determine the final product brand.
