import AVFoundation
import Foundation
import MurmurSessions
import Speech

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
        if didReceiveAudio {
            do { try await analyzer?.finalizeAndFinishThroughEndOfInput() }
            catch {
                Log.speech.error("meeting transcriber finalize failed: \(error.localizedDescription)")
                await analyzer?.cancelAndFinishNow()
            }
        } else {
            await analyzer?.cancelAndFinishNow()
        }
        await resultsTask?.value
        analyzer = nil
        transcriber = nil
        resultsTask = nil
        closeEvents()
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
