import AVFoundation
import Foundation
import MurmurSessions
import Speech
import Synchronization

/// What a meeting transcriber emits: live partial text for the notepad's optional live
/// view, and finalised segments with positions in the meeting for the store.
enum MeetingTranscriptEvent: Sendable {
    case partial(String)
    case final(TranscriptSegment)
}

/// The dictation engines collapse everything into one growing string, which is right for a
/// sentence you're about to paste and wrong for an hour you want to search. This protocol
/// keeps time: every finalised piece of speech knows when in the meeting it was said.
protocol MeetingTranscriber: Actor {
    func preferredInputFormat() async -> AVAudioFormat?
    /// - Parameters:
    ///   - source: which stream this instance is listening to.
    ///   - offset: seconds into the session when this transcriber's audio starts, so its
    ///     own zero-based times can be placed on the session clock.
    func start(source: AudioStreamSource, offset: TimeInterval) async throws -> AsyncStream<MeetingTranscriptEvent>
    func feed(_ chunk: AudioChunk) async
    func finish() async
}

/// Apple's `SpeechAnalyzer` with audio time ranges switched on.
///
/// No download, true streaming, and every result carries the range of audio it came from —
/// which is exactly what makes this the right default for meetings even though Parakeet is
/// more accurate on English. Long-form input is what the analyzer was built for.
actor AppleMeetingTranscriber: MeetingTranscriber {
    private let locale: Locale
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var events: AsyncStream<MeetingTranscriptEvent>.Continuation?

    private var source: AudioStreamSource = .call
    private var offset: TimeInterval = 0
    private var didReceiveAudio = false

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func preferredInputFormat() async -> AVAudioFormat? {
        let module = transcriber ?? Self.makeTranscriber(locale: locale)
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
    }

    func start(source: AudioStreamSource, offset: TimeInterval) async throws -> AsyncStream<MeetingTranscriptEvent> {
        guard SpeechTranscriber.isAvailable else { throw TranscriptionError.localeUnsupported(locale) }
        self.source = source
        self.offset = offset

        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? Locale(identifier: "en-US")
        let transcriber = Self.makeTranscriber(locale: resolved)
        self.transcriber = transcriber
        try await Self.ensureModelInstalled(for: transcriber)

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = inputContinuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        if let context = await Self.context() { try? await analyzer.setContext(context) }

        let (stream, continuation) = AsyncStream<MeetingTranscriptEvent>.makeStream()
        events = continuation
        didReceiveAudio = false

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { break }
                    await self.absorb(result)
                }
            } catch {
                Log.speech.error("meeting transcriber results failed: \(error.localizedDescription)")
            }
            await self?.closeEvents()
        }

        try await analyzer.start(inputSequence: inputStream)
        Log.speech.info("meeting transcriber (Apple) started for \(source.rawValue, privacy: .public) at +\(offset, format: .fixed(precision: 1))s")
        return stream
    }

    func feed(_ chunk: AudioChunk) async {
        guard chunk.buffer.frameLength > 0 else { return }
        didReceiveAudio = true
        input?.yield(AnalyzerInput(buffer: chunk.buffer))
    }

    func finish() async {
        input?.finish()
        input = nil
        let began = ContinuousClock.now
        let analyzer = self.analyzer
        if didReceiveAudio {
            // Finalising flushes the last words; it is normally sub-second, but an analyzer
            // that never sees end-of-input can sit forever. Bound it, then cut it.
            let finalised = await Self.within(.seconds(10)) {
                do { try await analyzer?.finalizeAndFinishThroughEndOfInput() }
                catch { Log.speech.error("meeting transcriber finalize failed: \(error.localizedDescription)") }
            }
            if !finalised {
                Log.speech.error("meeting transcriber (\(self.source.rawValue, privacy: .public)) finalize timed out; cancelling")
                _ = await Self.within(.seconds(3)) { await analyzer?.cancelAndFinishNow() }
            }
        } else {
            // An analyzer that was started but never fed can refuse to cancel promptly.
            // Nothing is lost by walking away from it.
            let cancelled = await Self.within(.seconds(3)) { await analyzer?.cancelAndFinishNow() }
            if !cancelled {
                Log.speech.error("meeting transcriber (\(self.source.rawValue, privacy: .public)) would not cancel; abandoning it")
            }
        }
        // The results stream ends with the analyzer. Give it a moment, then stop waiting.
        let results = resultsTask
        let drained = await Self.within(.seconds(3)) { await results?.value }
        if !drained { results?.cancel() }
        let took = ContinuousClock.now - began
        Log.speech.info("meeting transcriber (Apple) finished for \(self.source.rawValue, privacy: .public) in \(took.components.seconds).\(took.components.attoseconds / 100_000_000_000_000_000)s")
        self.analyzer = nil
        transcriber = nil
        resultsTask = nil
        closeEvents()
    }

    /// Runs `work` with a ceiling. Returns false when the ceiling was hit first — and, unlike
    /// a task group, does not then wait for the work: a task group joins every child before
    /// it returns, which is precisely the hang this exists to escape. The abandoned work
    /// finishes (or doesn't) on its own.
    private static func within(_ limit: Duration, _ work: @escaping @Sendable () async -> Void) async -> Bool {
        let once = Once()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Task { await work(); if once.claim() { continuation.resume(returning: true) } }
            Task { try? await Task.sleep(for: limit); if once.claim() { continuation.resume(returning: false) } }
        }
    }

    /// First caller wins.
    private final class Once: Sendable {
        private let done = Mutex(false)
        func claim() -> Bool {
            done.withLock { taken in
                if taken { return false }
                taken = true
                return true
            }
        }
    }

    private func closeEvents() {
        events?.finish()
        events = nil
    }

    private func absorb(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard result.isFinal else {
            events?.yield(.partial(text))
            return
        }
        let range = result.range
        let start = offset + max(0, range.start.seconds)
        let end = offset + max(range.start.seconds, range.end.seconds)
        events?.yield(.final(TranscriptSegment(start: start, end: end, source: source, text: text)))
    }

    private static func context() async -> AnalysisContext? {
        let phrases = await MainActor.run { DictionaryStore.shared.biasPhrases }
        guard !phrases.isEmpty else { return nil }
        let context = AnalysisContext()
        context.contextualStrings[.general] = phrases
        return context
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
    }

    private static func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let alreadyThere = transcriber.selectedLocales.allSatisfy { locale in
            installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        }
        guard !alreadyThere else { return }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw TranscriptionError.modelInstallFailed(error.localizedDescription)
        }
    }
}
