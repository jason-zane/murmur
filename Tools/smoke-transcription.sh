#!/bin/bash
# Real on-device recognition plus repeated capture on the current system microphone.
# Run with the microphone connected. No audio or transcript is uploaded.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/voice-notes-speech.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT
/usr/bin/say -v Samantha -o "$fixture_dir/speech.aiff" \
  'The purple bicycle is parked beside the station. Please send the updated meeting notes on Thursday.'
MURMUR_MIC_CAPTURE_SMOKE=1 MURMUR_SPEECH_FIXTURE="$fixture_dir/speech.aiff" \
  make test TEST_ARGS='--filter TranscriptionSmokeTests'
