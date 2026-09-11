import MurmurDictionary
import AVFoundation
import AppKit
import Foundation
import Observation
import MurmurSessions
import Synchronization

/// Builds the engine named by the current setting.
///
/// Deliberately at file scope rather than a static on `DictationController`: the class is
/// `@MainActor`, which would make a static method main-actor-isolated and therefore
/// ineligible to be `@Sendable`. Reading the setting per-utterance is what lets the menu's
/// engine picker take effect on the very next hold instead of needing a restart.
@MainActor
func engineForCurrentSetting() -> any TranscriptionEngine {
    // Always invoked from `beginDictation`, which runs on the main actor.
    // Parakeet only when its models are on disk; otherwise Apple, which needs nothing
    // downloaded. The setting is honoured, not trusted.
    switch Settings.shared.engine {
    case .apple: AppleSpeechEngine()
    case .parakeet: ParakeetModels.isDownloaded ? ParakeetEngine() : AppleSpeechEngine()
    }
}

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case finishing
        case error(String)

        var isActive: Bool {
            switch self {
            case .starting, .listening, .finishing: true
            case .idle, .error: false
            }
        }
    }

    private(set) var state: State = .idle
    /// Live transcript, updated as the engine revises it. Drives the HUD.
    private(set) var transcript = ""
    /// Smoothed 0…1 mic level for the waveform.
    private(set) var level: Float = 0
    /// Kept in the main window after the temporary HUD message disappears.
    private(set) var lastError: String?

    private let hotkey = HotkeyMonitor()
    private let pasteShortcut = ShortcutMonitor()
    private let capture: any DictationAudioCapturing
    private let makeEngine: @MainActor @Sendable () -> any TranscriptionEngine
    private let requestMicrophone: @MainActor @Sendable () async -> Bool
    private let insertText: @MainActor (String) -> Void
    private let saveRun: @MainActor (DictationRun) -> Void
    private let finishLimit: Duration
    private let startupLimit: Duration
    private var sessionID: UUID?
    private var setupTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?
    private var captureWatchdog: Task<Void, Never>?

    /// Injected only by tests; production reads the setting per-utterance below.
    private let formatter: (any TextFormatter)?

    /// Chosen per-utterance so the menu toggle applies to the very next hold.
    private var activeFormatter: any TextFormatter {
        if let formatter { return formatter }
        return Settings.shared.smartCleanup
            ? FoundationModelFormatter()
            : RuleBasedFormatter()
    }

    private var engine: (any TranscriptionEngine)?
    private var consumeTask: Task<Void, Never>?
    /// Returns the ordered recording when compare mode is on, empty otherwise.
    private var feedTask: Task<[AudioChunk], Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    /// Timestamps for the dashboard: when the key went down, and when it came up.
    private var holdStarted: Date?
    private var releasedAt: Date?
    private var engineName = ""
    /// One line for the dictation bar before any words arrive — why this dictation is
    /// not quite what the settings say. Shown once per launch, then dropped.
    private(set) var notice: String?
    private var warnedParakeetMissing = false

    /// Compare mode only: the recording, kept so every engine sees identical audio.
    private var recorded: [AudioChunk] = []
    private var isComparing = false

    /// A dictation longer than this is assumed to be a stuck session, not a monologue.
    /// Five minutes: long enough for a dictated email or a voice note, short enough that a
    /// lost key-up cannot leave the mic open indefinitely.
    ///
    /// Nothing guarantees a key-up arrives — a system panel can consume it, and the app can
    /// be suspended mid-hold. Without a ceiling the mic stays open indefinitely and no new
    /// dictation can start, which is exactly the failure this is here to end.
    private static let maxHoldDuration: Duration = .seconds(300)

    /// Ceiling on the finish path — draining audio, finalizing the engine, waiting for the
    /// transcript. Generous, because Parakeet transcribes inside `finish()` and smart
    /// cleanup adds seconds on top; but finite, because an engine that never returns must
    /// not be able to wedge the app.
    private var watchdog: Task<Void, Never>?

    /// A press shorter than this counts as a tap rather than a hold, in `.hybrid`.
    private static let tapThreshold: TimeInterval = 0.4

    private var pressedAt: Date?
    /// True once a tap has latched the mic open, so the next press stops instead of starting.
    private var isLatched = false
    /// Set when a release arrives while the engine is still starting up. See `endDictation`.
    private var pendingStop = false
    init(
        formatter: (any TextFormatter)? = nil,
        makeEngine: @escaping @MainActor @Sendable () -> any TranscriptionEngine = engineForCurrentSetting,
        capture: any DictationAudioCapturing = AudioCapture(),
        requestMicrophone: @escaping @MainActor @Sendable () async -> Bool = { await Permissions.requestMicrophone() },
        insertText: @escaping @MainActor (String) -> Void = { TextInjector.insert($0) },
        saveRun: @escaping @MainActor (DictationRun) -> Void = { RunLog.record($0) },
        finishLimit: Duration = .seconds(25),
        startupLimit: Duration = .seconds(60)
    ) {
        self.formatter = formatter
        self.makeEngine = makeEngine
        self.capture = capture
        self.requestMicrophone = requestMicrophone
        self.insertText = insertText
        self.saveRun = saveRun
        self.finishLimit = finishLimit
        self.startupLimit = startupLimit
    }

    // MARK: - Lifecycle

    /// - Returns: `false` if the hotkey tap couldn't be installed (missing Accessibility).
    @discardableResult
    func activate() -> Bool {
        hotkey.triggers = Settings.shared.triggers
        hotkey.onPress = { [weak self] trigger in self?.handleTriggerPress(trigger) }
        hotkey.onRelease = { [weak self] trigger in self?.handleTriggerRelease(trigger) }
        let armed = hotkey.start()
        reloadPasteShortcut()
        return armed
    }

    func deactivate() {
        pasteShortcut.stop()
        hotkey.stop()
        cancelDictation()
    }

    /// Re-arms the tap after the user picks a different push-to-talk key.
    @discardableResult
    func reloadHotkey() -> Bool {
        hotkey.stop()
        return activate()
    }

    /// Route the next held key or mouse button to `handler` instead of starting a dictation.
    /// This is how Settings records a trigger by having the user press it.
    func beginTriggerCapture(_ handler: @escaping (TriggerCapture) -> Void) {
        hotkey.captureHandler = handler
    }

    func cancelTriggerCapture() {
        hotkey.captureHandler = nil
    }

    @discardableResult
    func reloadPasteShortcut() -> Bool {
        pasteShortcut.shortcut = Settings.shared.pasteShortcut
        pasteShortcut.isEnabled = Settings.shared.pasteShortcutEnabled
        pasteShortcut.onTrigger = { [weak self] in self?.pasteLastDictation() }
        return pasteShortcut.reload()
    }

    /// Re-insert the most recent transcription wherever the cursor is.
    ///
    /// Reads the log rather than the in-memory store, because the store is only refreshed
    /// when a window is open and this fires from a global shortcut with no window involved.
    func pasteLastDictation() {
        guard let last = RunLog.load().last(where: {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            Log.app.info("paste-last: nothing recorded yet")
            NSSound(named: "Funk")?.play()
            return
        }
        Log.app.info("paste-last: re-inserting \(last.text.count) chars")
        TextInjector.insert(last.text)
        if Settings.shared.soundEnabled { NSSound(named: "Pop")?.play() }
    }

    // MARK: - Activation

    /// A press either stops a latched session or starts a new one.
    ///
    /// Presses arriving while a previous dictation is still `.finishing` are dropped, rather
    /// than queued — the engine and cleanup pass can take seconds, and starting a second
    /// capture underneath the first is how you get two transcripts racing for one text field.
    private func handleTriggerPress(_ trigger: PushToTalkTrigger) {
        if state == .finishing { forceReset(); return }
        if isLatched || (Settings.shared.activation == .toggle && state.isActive) {
            isLatched = false
            endDictation()
            return
        }
        guard !state.isActive else { return }
        pressedAt = Date()
        beginDictation()
    }

    private func handleTriggerRelease(_ trigger: PushToTalkTrigger) {
        guard state.isActive else { return }

        switch Settings.shared.activation {
        case .hold:
            endDictation()

        case .toggle:
            // Releasing never stops a toggle session; the next press does.
            isLatched = true

        case .hybrid:
            // A quick tap latches the mic open; a real hold ends on release. Without this a
            // tap recorded roughly a tenth of a second of silence and looked like a no-op.
            let held = pressedAt.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
            if held < Self.tapThreshold {
                isLatched = true
            } else {
                endDictation()
            }
        }
    }

    // MARK: - Button-driven recording

    /// Starts a recording from a Record button rather than the hotkey.
    ///
    /// Wispr Flow's hotkey is held down for the duration **only in compare mode**. Reaching
    /// into another app is a comparison affordance; during ordinary dictation it would mean
    /// every recording silently shipped your audio to a third party's servers.
    func startButtonRecording() {
        guard !state.isActive else { return }
        if Settings.shared.compareMode { WisprTrigger.press() }
        beginDictation()
    }

    /// Releases Wispr's hotkey first, so its upload starts while our own engines are still
    /// finishing — otherwise every run would wait the full round trip end to end.
    func stopButtonRecording() {
        WisprTrigger.release()
        if state == .starting || state == .finishing { forceReset(); return }
        endDictation()
    }

    /// One entry point for the Record button, so its two halves can never disagree with the
    /// state machine about whether a recording is in progress.
    func toggleRecording() {
        if state.isActive {
            stopButtonRecording()
        } else {
            startButtonRecording()
        }
    }

    /// Abandon whatever is in flight and return to idle, discarding the utterance.
    ///
    /// The escape hatch for a session that can't finish normally — the engine never
    /// returned, or a key-up was lost. It also clears the hotkey's press state, because a
    /// monitor that still believes the key is down would ignore the next press.
    func forceReset() {
        isLatched = false
        pendingStop = false
        Log.app.info("force reset from \(String(describing: self.state), privacy: .public)")
        watchdog?.cancel()
        watchdog = nil
        hotkey.clearPressState()
        WisprTrigger.release()
        cancelDictation()
        lastError = nil
    }

    // MARK: - Dictation

    private func beginDictation() {
        guard !state.isActive else { return }
        errorDismissTask?.cancel()
        lastError = nil
        let runID = UUID()
        sessionID = runID
        state = .starting
        pendingStop = false
        transcript = ""
        holdStarted = Date()
        isComparing = Settings.shared.compareMode
        recorded.removeAll(keepingCapacity: true)
        let choice = Settings.shared.engine
        let fellBack = choice == .parakeet && !ParakeetModels.isDownloaded
        engineName = isComparing ? "Comparing…" : (fellBack ? SpeechEngineChoice.apple : choice).displayName
        notice = nil
        if fellBack, !warnedParakeetMissing {
            warnedParakeetMissing = true
            notice = "Parakeet isn't downloaded — using Apple"
        }

        let engine = makeEngine()
        self.engine = engine
        setupTask = Task { @MainActor in
            do {
                let allowed = await requestMicrophone()
                guard self.sessionID == runID, !Task.isCancelled else { return }
                guard allowed else {
                    fail("Microphone access is off. Enable it in System Settings ▸ Privacy & Security ▸ Microphone.")
                    return
                }

                let chunks = try await AsyncDeadline.run(for: startupLimit) {
                    do {
                        let stream = try await engine.start()
                        try Task.checkCancellation()
                        return stream
                    } catch {
                        await engine.cancel()
                        throw error
                    }
                }
                guard self.sessionID == runID, !Task.isCancelled else { await engine.cancel(); return }

                // Compare mode captures in *Apple's* format, not a format of our choosing.
                //
                // SpeechAnalyzer enforces `Audio sample data must be 16-bit signed integers`
                // as a hard precondition — feeding it float32 doesn't fail gracefully, it
                // kills the process. Parakeet is the flexible one (its `feed` converts
                // int16/int32/float32), so the strict engine picks the format and the
                // tolerant engine adapts. Both still replay the identical buffers.
                let formatOwner: any TranscriptionEngine = isComparing ? AppleSpeechEngine() : engine
                guard let format = await formatOwner.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }
                guard self.sessionID == runID, !Task.isCancelled else { await engine.cancel(); return }

                // Audio must reach the engine in capture order. A stream plus a single
                // draining task guarantees that; spawning a Task per buffer would not.
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                self.audioContinuation = audioContinuation

                // The recording is accumulated *inside* the ordered drain, not by spawning
                // a task per buffer. Unstructured tasks have no ordering guarantee, so
                // collecting them separately could assemble the replay audio out of order
                // and silently produce word-salad from the comparison.
                let comparing = isComparing
                self.feedTask = Task.detached(priority: .userInitiated) {
                    var recording: [AudioChunk] = []
                    for await chunk in audioStream {
                        if comparing { recording.append(chunk) }
                        await engine.feed(chunk)
                    }
                    return recording
                }

                let receipt = AudioReceipt()
                try await capture.start(
                    outputFormat: format,
                    onBuffer: { chunk in
                        receipt.received()
                        audioContinuation.yield(chunk)
                    },
                    onLevel: { [weak self] level in
                        Task { @MainActor in
                            if self?.sessionID == runID, self?.state == .listening { self?.updateLevel(level) }
                        }
                    }
                )

                // Bail out if the user already let go while we were spinning up.
                guard self.sessionID == runID, !Task.isCancelled else { await engine.cancel(); return }

                self.state = .listening
                if Settings.shared.soundEnabled { NSSound(named: "Tink")?.play() }
                self.armWatchdog()
                self.watchCapture(receipt, for: runID)

                self.consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            guard self.sessionID == runID, !Task.isCancelled else { break }
                            self.transcript = chunk.text
                        }
                    } catch {
                        if self.sessionID == runID { self.fail(error.localizedDescription) }
                    }
                }

                // A release that arrived during setup was deferred rather than raced.
                // Honour it now — and only now.
                //
                // This MUST come after `consumeTask` is assigned. Running it earlier ended
                // the dictation while `consumeTask` was still nil, so the finish path had
                // nothing to await; the setup task then carried on and installed a consumer
                // for a stream whose engine had already been finalized. That consumer never
                // terminated, `await consumeTask?.value` blocked forever, and the state
                // machine sat in `.finishing` — mic open, every later press ignored, only a
                // relaunch clearing it.
                if self.pendingStop {
                    self.pendingStop = false
                    self.endDictation()
                }
            } catch {
                if self.sessionID == runID {
                    self.fail(error is AsyncDeadline.TimedOut
                        ? "The speech engine could not get ready. Try again or select the other model in Settings."
                        : error.localizedDescription)
                }
            }
        }
    }

    /// Drain this recording in order, with a deadline that also responds to cancellation.
    private func drainWithDeadline() async throws -> [AudioChunk] {
        // Capture this session's handles before awaiting. A late framework completion
        // must never finish a newer recording or write into its transcript.
        let feed = feedTask, consume = consumeTask, engine = engine
        audioContinuation?.finish()
        audioContinuation = nil
        return try await AsyncDeadline.run(for: finishLimit) {
            let recording = await feed?.value ?? []
            await engine?.finish()
            await consume?.value
            return recording
        }
    }

    private final class AudioReceipt: Sendable {
        private let last = Mutex(ContinuousClock.now)
        func received() { last.withLock { $0 = .now } }
        var stalled: Bool { last.withLock { .now - $0 > .seconds(2) } }
    }

    private func watchCapture(_ receipt: AudioReceipt, for runID: UUID) {
        captureWatchdog?.cancel()
        captureWatchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.sessionID == runID, self.state == .listening else { return }
                if receipt.stalled {
                    self.fail("The microphone stopped sending audio. Check its connection and try again.")
                    return
                }
            }
        }
    }

    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.maxHoldDuration)
            guard let self, !Task.isCancelled, self.state == .listening else { return }
            Log.app.error("dictation exceeded the maximum hold — ending automatically")
            self.hotkey.clearPressState()
            self.endDictation()
        }
    }

    private func endDictation() {
        // A release during `.starting` can't tear down a session that isn't built yet —
        // the setup task is mid-flight and would race us, sometimes leaving the state
        // machine wedged. Defer instead; the setup task runs this the moment it's listening.
        if case .starting = state {
            pendingStop = true
            return
        }

        // `.finishing` is "active", so without this a second press during processing would
        // run the whole tail again — re-reading `transcript` before the first pass cleared
        // it and pasting the same utterance twice. The window is wide: Parakeet transcribes
        // inside `finish()`, and smart cleanup adds up to 4s on top.
        guard state.isActive, state != .finishing else { return }
        watchdog?.cancel()
        watchdog = nil
        captureWatchdog?.cancel()
        captureWatchdog = nil
        state = .finishing
        capture.stop()
        level = 0
        releasedAt = Date()

        guard let runID = sessionID else { return }
        finishTask = Task { @MainActor in
            do {
                let recording = try await drainWithDeadline()
                guard self.sessionID == runID, !Task.isCancelled else { return }
                recorded = recording
            }
            catch {
                guard self.sessionID == runID else { return }
                Log.speech.error("dictation finish failed: \(error.localizedDescription)")
                fail("Transcription could not finish. Try again; you can cancel at any time.")
                return
            }
            guard self.sessionID == runID, !Task.isCancelled else { return }
            consumeTask = nil
            feedTask = nil
            engine = nil

            if isComparing {
                await runComparison(for: runID)
                return
            }

            let raw = transcript
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail("No speech was heard. Check the selected microphone in Settings and try again.")
                return
            }

            let cleaned = Settings.shared.cleanupEnabled
                ? await activeFormatter.format(raw)
                : raw
            guard self.sessionID == runID, !Task.isCancelled else { return }

            // The dictionary runs last, and runs regardless of the cleanup setting. Biasing
            // only raises the odds of the right word; this is the pass that guarantees it,
            // so it must not be something the user can accidentally switch off.
            let (output, corrections) = DictionaryStore.shared.corrector.apply(to: cleaned)
            if !corrections.isEmpty {
                Log.speech.info("dictionary · \(corrections.count, privacy: .public) correction(s) applied")
            }

            recordRun(text: output, corrections: corrections)
            insertText(output)
            if Settings.shared.soundEnabled { NSSound(named: "Pop")?.play() }

            state = .idle
            sessionID = nil
            transcript = ""
        }
    }

    private func cancelDictation() {
        sessionID = nil
        setupTask?.cancel()
        setupTask = nil
        finishTask?.cancel()
        finishTask = nil
        captureWatchdog?.cancel()
        captureWatchdog = nil
        errorDismissTask?.cancel()
        errorDismissTask = nil
        watchdog?.cancel()
        watchdog = nil
        isLatched = false
        pendingStop = false
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil

        let engine = self.engine
        self.engine = nil
        Task { await engine?.cancel() }

        state = .idle
        transcript = ""
        level = 0
    }

    // MARK: - Helpers

    private func retainForComparison(_ chunk: AudioChunk) {
        guard isComparing else { return }
        recorded.append(chunk)
    }

    /// Replays the recording through every engine and files the results as one group.
    ///
    /// Nothing is injected in this mode — the point is to read the outputs side by side,
    /// and typing one of them into whatever had focus would be a surprise.
    private func runComparison(for runID: UUID) async {
        let chunks = recorded
        recorded.removeAll(keepingCapacity: false)

        guard !chunks.isEmpty, let holdStarted, let releasedAt else {
            state = .idle
            transcript = ""
            return
        }

        transcript = "Running both engines…"

        let group = UUID().uuidString
        let held = releasedAt.timeIntervalSince(holdStarted)

        // Filed one at a time as each engine finishes, so the window fills in progressively
        // rather than snapping both rows into place at the end.
        let results = await EngineComparison.run(chunks: chunks) { result in
            guard self.sessionID == runID else { return }
            RunLog.record(
                DictationRun(
                    date: releasedAt,
                    engine: result.engine,
                    audioSeconds: held,
                    processSeconds: result.seconds,
                    text: result.text,
                    group: group
                )
            )
        }
        guard sessionID == runID, !Task.isCancelled else { return }

        for result in results {
            Log.speech.info("""
                compare · \(result.engine, privacy: .public): \
                \(result.seconds, format: .fixed(precision: 2))s — \
                \(result.text, privacy: .public)
                """)
        }

        // Wispr Flow, if its hotkey was held for this same utterance. It transcribes in the
        // cloud, so its row lands after both local engines have already finished — the wait
        // happens here rather than blocking the rows above from appearing.
        if WisprReader.isInstalled {
            transcript = "Waiting for Wispr Flow…"
            if let wispr = await WisprReader.result(after: holdStarted, timeout: 8) {
                guard sessionID == runID, !Task.isCancelled else { return }
                RunLog.record(
                    DictationRun(
                        date: releasedAt,
                        engine: wispr.engine,
                        audioSeconds: held,
                        processSeconds: wispr.seconds,
                        text: wispr.text,
                        group: group
                    )
                )
                Log.speech.info("""
                    compare · \(wispr.engine, privacy: .public): \
                    \(wispr.seconds, format: .fixed(precision: 2))s — \
                    \(wispr.text, privacy: .public)
                    """)
            } else {
                Log.speech.info("compare · Wispr Flow: no result (hotkey not held, or timed out)")
            }
        }
        guard sessionID == runID, !Task.isCancelled else { return }

        self.holdStarted = nil
        self.releasedAt = nil
        isComparing = false
        state = .idle
        transcript = ""

        if Settings.shared.soundEnabled { NSSound(named: "Glass")?.play() }
    }

    /// Files the finished utterance for the dashboard.
    ///
    /// `processSeconds` is measured from key release, not from capture start — that's the
    /// wait the user actually experiences, and it's the only number on which a streaming
    /// engine and a batch engine can be compared honestly.
    private func recordRun(text: String, corrections: [AppliedCorrection] = []) {
        guard let holdStarted, let releasedAt else { return }
        saveRun(
            DictationRun(
                date: releasedAt,
                engine: engineName,
                audioSeconds: releasedAt.timeIntervalSince(holdStarted),
                processSeconds: Date().timeIntervalSince(releasedAt),
                text: text,
                corrections: corrections.isEmpty ? nil : corrections
            )
        )
        self.holdStarted = nil
        self.releasedAt = nil
    }

    /// Light smoothing so the waveform glides instead of strobing at buffer rate.
    private func updateLevel(_ new: Float) {
        level += (new - level) * 0.35
    }

    private func fail(_ message: String) {
        Log.app.error("\(message)")
        cancelDictation()
        hotkey.clearPressState()
        lastError = message
        state = .error(message)
        level = 0

        errorDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if case .error = state { state = .idle }
        }
    }
}
