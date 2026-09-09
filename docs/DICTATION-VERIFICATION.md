# Dictation repair — 9 September 2026

The installed app's logs confirmed the reported failure: at 16:20:17 and 16:20:46,
the finish path exceeded 25 seconds and discarded the recordings. Stop did nothing
in `.finishing`, because it called an end method that explicitly ignored that state.

## Reproduced defects

- Repeated live recording with Jason's AirPods Pro delivered roughly 48,000 frames
  in the first three-second attempt, but only 1,360 frames in each later attempt.
  The first buffer arrived, then the AVAudioEngine microphone graph stopped delivering.
- Starting and immediately finishing Apple's speech engine without audio left its
  public result stream open. The framework cancellation returned, but the controller
  continued waiting for the result consumer.
- Resetting did not invalidate all in-flight startup, finish and cleanup work. A
  late completion could change state or insert words after cancellation.

## Installed changes

- Input-only AVCaptureSession replaces the duplex AVAudioEngine microphone graph.
  Session operations run on a serial queue, and conversion follows the format of
  each actual buffer. Each recording selects the current default input device.
- Empty/cancelled Apple sessions explicitly close their output stream. Engine
  finalization is bounded, and both engines have a cancellation operation.
- Each dictation has a generation ID. Cancel invalidates its startup, finish,
  formatting and delivery tasks; late results cannot affect the next dictation.
- The main window and floating HUD offer Cancel while preparing/transcribing.
  The floating HUD now accepts clicks while preserving the target field's focus.
- A microphone that stops delivering buffers produces an actionable error after
  approximately two seconds. Errors remain visible in the Dictation window.

## Evidence

- Before changing capture, the repeated real AirPods test failed twice. After the
  change, all three recordings continuously delivered about 49,000–51,000 frames
  per three-second recording. Each speech finalization completed in under 0.1 seconds.
- The empty-result-stream regression failed before the fix and now completes in
  approximately 0.003 seconds.
- Apple and Parakeet each correctly transcribed the complete synthetic spoken
  sentence, including the last word, Thursday. The meeting transcriber produced
  final transcript segments from the same real audio.
- Five controller tests cover cancellation during startup/transcription/cleanup,
  restart after a cancelled recording, late completion after timeout, and a stalled
  microphone. They replace only external hardware/insertion boundaries and do not
  write synthetic content to the user's history.
- Full `make test` reported 55 tests across 11 suites passing with microphone and
  speech-fixture checks enabled. The unrelated optional summary-model checks were
  not repeated. `make install LAUNCH=0` installed the corrected app in `/Applications`
  with the stable Apple Development signature, and it was launched normally.

Run the model and microphone checks again when a capture regression is suspected:

```sh
bash Tools/smoke-transcription.sh
make test TEST_ARGS='--filter DictationWorkflowTests'
```

## Live dictation confirmed

The user tested two consecutive dictations using Left Option in a text field and
confirmed: “Both dictations work.” Each inserted the spoken words and returned to
idle. The active input was Jason's AirPods Pro. The temporary diagnostic web server
has been stopped. This confirms the installed dictation workflow; a real Google
Meet with another participant remains a separate acceptance check.
