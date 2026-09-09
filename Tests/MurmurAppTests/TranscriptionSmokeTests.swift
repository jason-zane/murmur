import AVFoundation
import Foundation
import MurmurSessions
import Testing
import Synchronization
@testable import Murmur

/// Opt-in checks with real speech and the installed on-device models. Silence alone
/// cannot establish that a recognizer works or that it preserves the end of a sentence.
@MainActor
@Suite(.serialized)
struct TranscriptionSmokeTests {
    private var fixture: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["MURMUR_SPEECH_FIXTURE"]!)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_MIC_CAPTURE_SMOKE"] == "1"))
    func microphoneDeliversAudio() async throws {
        print("Microphone permission: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue); input: \(AudioCapture.currentInputName ?? "none")")
        try #require(await Permissions.requestMicrophone())
        let capture = AudioCapture()
        let samples = Mutex(0)
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        try await capture.start(outputFormat: format, onBuffer: { chunk in
            samples.withLock { $0 += Int(chunk.buffer.frameLength) }
        }, onLevel: { _ in })
        defer { capture.stop() }
        try await Task.sleep(for: .seconds(3))
        let count = samples.withLock { $0 }
        print("Microphone supplied \(count) frames in 3 seconds")
        #expect(count >= 16_000)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_MIC_CAPTURE_SMOKE"] == "1"))
    func liveMicrophoneCanFinishRepeatedly() async throws {
        try #require(await Permissions.requestMicrophone())
        for attempt in 1...3 {
            let engine = AppleSpeechEngine()
            let stream = try await engine.start()
            let result = Task { () throws -> Int in
                var count = 0
                for try await chunk in stream { count = chunk.text.count }
                return count
            }
            let format = try #require(await engine.preferredInputFormat())
            let capture = AudioCapture()
            let (audio, continuation) = AsyncStream<AudioChunk>.makeStream()
            let feed = Task { for await chunk in audio { await engine.feed(chunk) } }
            let frames = Mutex(0)
            try await capture.start(outputFormat: format, onBuffer: { chunk in
                frames.withLock { $0 += Int(chunk.buffer.frameLength) }
                continuation.yield(chunk)
            }, onLevel: { _ in })
            try await Task.sleep(for: .seconds(3))
            capture.stop()
            continuation.finish()
            await feed.value
            let began = ContinuousClock.now
            try await AsyncDeadline.run(for: .seconds(8)) { await engine.finish() }
            let count = try await AsyncDeadline.run(for: .seconds(2)) { try await result.value }
            print("Live capture \(attempt): \(frames.withLock { $0 }) frames, \(count) characters, finish \(ContinuousClock.now - began)")
            #expect(frames.withLock { $0 } >= 16_000)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_MIC_CAPTURE_SMOKE"] == "1"))
    func emptySpeechSessionFinishesPromptly() async throws {
        let engine = AppleSpeechEngine()
        let stream = try await engine.start()
        let result = Task { for try await _ in stream {} }
        try await AsyncDeadline.run(for: .seconds(3)) { await engine.finish() }
        try await AsyncDeadline.run(for: .seconds(2)) { try await result.value }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_SPEECH_FIXTURE"] != nil),
          arguments: [SpeechEngineChoice.apple, .parakeet])
    func speechProducesTextAndFinishes(choice: SpeechEngineChoice) async throws {
        let engine: any TranscriptionEngine = choice == .apple ? AppleSpeechEngine() : ParakeetEngine()
        let stream = try await AsyncDeadline.run(for: .seconds(60)) { try await engine.start() }
        let result = Task { () throws -> String in
            var text = ""
            for try await chunk in stream { text = chunk.text }
            return text
        }
        let format = try #require(await engine.preferredInputFormat())
        let chunks = try audioChunks(format: format)
        print("\(choice.rawValue): feeding \(chunks.count) speech buffers at \(format.sampleRate) Hz")
        for chunk in chunks { await engine.feed(chunk) }
        let began = ContinuousClock.now
        try await AsyncDeadline.run(for: .seconds(20)) { await engine.finish() }
        let text = try await AsyncDeadline.run(for: .seconds(3)) { try await result.value }
        print("\(choice.rawValue): finished in \(ContinuousClock.now - began): \(text)")
        #expect(text.localizedCaseInsensitiveContains("purple"))
        #expect(text.localizedCaseInsensitiveContains("bicycle"))
        #expect(text.localizedCaseInsensitiveContains("station"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_SPEECH_FIXTURE"] != nil))
    func meetingSpeechProducesFinalSegments() async throws {
        let engine = AppleMeetingTranscriber()
        let stream = try await AsyncDeadline.run(for: .seconds(60)) { try await engine.start(source: .you, offset: 0) }
        let result = Task { () -> (String, [String]) in
            var text = "", failures: [String] = []
            for await event in stream {
                switch event {
                case .final(let segment): text += " " + segment.text
                case .failed(_, let message): failures.append(message)
                case .partial: break
                }
            }
            return (text, failures)
        }
        let format = try #require(await engine.preferredInputFormat())
        for chunk in try audioChunks(format: format) { await engine.feed(chunk) }
        try await AsyncDeadline.run(for: .seconds(20)) { await engine.finish() }
        let (text, failures) = try await AsyncDeadline.run(for: .seconds(3)) { await result.value }
        print("Meeting speech: \(text), failures: \(failures)")
        #expect(failures.isEmpty)
        #expect(text.localizedCaseInsensitiveContains("purple"))
        #expect(text.localizedCaseInsensitiveContains("station"))
    }

    private func audioChunks(format: AVAudioFormat) throws -> [AudioChunk] {
        let file = try AVAudioFile(forReading: fixture)
        let converter = try #require(AVAudioConverter(from: file.processingFormat, to: format))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: input)
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / file.processingFormat.sampleRate)) + 64
        let output = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity))
        nonisolated(unsafe) let conversionInput = input
        let supplied = Mutex(false)
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            guard supplied.withLock({ value in
                if value { return false }
                value = true
                return true
            }) else { status.pointee = .endOfStream; return nil }
            status.pointee = .haveData
            return conversionInput
        }
        if let conversionError { throw conversionError }
        #expect(output.frameLength > 0)
        return [AudioChunk(buffer: output)]
    }
}
