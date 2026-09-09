import AVFoundation
import Foundation
import Synchronization
import Testing
@testable import Murmur

@MainActor
@Suite(.serialized)
struct DictationWorkflowTests {
    @Test func stopDuringTranscriptionCancelsImmediatelyAndNextRecordingWorks() async throws {
        let old = ControlledEngine(text: "Cancelled words", blockFinish: true)
        let next = ControlledEngine(text: "Next recording")
        let capture = MockMicrophone()
        var engines: [ControlledEngine] = [old, next]
        var inserted: [String] = [], saved: [String] = []
        let controller = DictationController(formatter: PassthroughFormatter(),
            makeEngine: { engines.removeFirst() }, capture: capture,
            requestMicrophone: { true }, insertText: { inserted.append($0) },
            saveRun: { saved.append($0.text) })
        controller.startButtonRecording()
        try await wait { controller.state == .listening }
        controller.stopButtonRecording()
        try await wait { await old.isFinishing }
        #expect(controller.state == .finishing)
        controller.stopButtonRecording()
        #expect(controller.state == .idle)
        controller.startButtonRecording()
        try await wait { controller.state == .listening }
        await old.releaseFinish()
        try await Task.sleep(for: .milliseconds(30))
        #expect(controller.state == .listening)
        #expect(inserted.isEmpty)
        controller.stopButtonRecording()
        try await wait { controller.state == .idle }
        #expect(inserted == ["Next recording"])
        #expect(saved == inserted)
        #expect(capture.startCount == 2)
    }

    @Test func cancelDuringStartupDoesNotStartTheMicrophoneLater() async throws {
        let engine = ControlledEngine(text: "Late startup", blockStart: true)
        let capture = MockMicrophone()
        var inserted: [String] = []
        let controller = DictationController(makeEngine: { engine }, capture: capture,
            requestMicrophone: { true }, insertText: { inserted.append($0) }, saveRun: { _ in })
        controller.startButtonRecording()
        try await wait { await engine.isStarting }
        controller.stopButtonRecording()
        #expect(controller.state == .idle)
        await engine.releaseStart()
        try await Task.sleep(for: .milliseconds(30))
        #expect(controller.state == .idle)
        #expect(capture.startCount == 0)
        #expect(inserted.isEmpty)
    }

    @Test func finishTimeoutReportsFailureAndLateResultCannotInsert() async throws {
        let engine = ControlledEngine(text: "Too late", blockFinish: true)
        var inserted: [String] = []
        let controller = DictationController(makeEngine: { engine }, capture: MockMicrophone(),
            requestMicrophone: { true }, insertText: { inserted.append($0) }, saveRun: { _ in },
            finishLimit: .milliseconds(30))
        controller.startButtonRecording()
        try await wait { controller.state == .listening }
        controller.stopButtonRecording()
        try await wait { controller.lastError != nil }
        #expect(!controller.state.isActive)
        await engine.releaseFinish()
        try await Task.sleep(for: .milliseconds(30))
        #expect(inserted.isEmpty)
        controller.forceReset()
    }

    @Test func cancelledCleanupCannotPasteAfterANewRecordingStarts() async throws {
        let formatter = SuspendedFormatter()
        let first = ControlledEngine(text: "Old cleanup")
        let next = ControlledEngine(text: "New recording")
        var engines = [first, next], inserted: [String] = []
        let controller = DictationController(formatter: formatter,
            makeEngine: { engines.removeFirst() }, capture: MockMicrophone(),
            requestMicrophone: { true }, insertText: { inserted.append($0) }, saveRun: { _ in })
        controller.startButtonRecording()
        try await wait { controller.state == .listening }
        controller.stopButtonRecording()
        try await wait { await formatter.isWaiting }
        controller.stopButtonRecording()
        controller.startButtonRecording()
        try await wait { controller.state == .listening }
        await formatter.release()
        try await Task.sleep(for: .milliseconds(30))
        #expect(controller.state == .listening)
        #expect(inserted.isEmpty)
        controller.forceReset()
    }

    @Test func missingMicrophoneBuffersProduceAnActionableError() async throws {
        let engine = ControlledEngine(text: "")
        let controller = DictationController(makeEngine: { engine }, capture: MockMicrophone(),
            requestMicrophone: { true }, insertText: { _ in }, saveRun: { _ in })
        controller.startButtonRecording()
        try await wait { controller.state == .listening }
        try await wait(limit: .seconds(4)) { controller.lastError != nil }
        #expect(controller.lastError?.contains("microphone") == true)
        #expect(!controller.state.isActive)
        controller.forceReset()
    }

    private func wait(limit: Duration = .seconds(1), until condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(await condition())
    }
}

private final class MockMicrophone: DictationAudioCapturing, Sendable {
    private let starts = Mutex(0)
    var startCount: Int { starts.withLock { $0 } }
    func start(outputFormat: AVAudioFormat, onBuffer: @escaping @Sendable (AudioChunk) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void) async throws { starts.withLock { $0 += 1 } }
    func stop() {}
}

/// Gates deliberately ignore task cancellation, as the stalled OS framework did.
private actor ControlledEngine: TranscriptionEngine {
    let text: String
    let blockStart: Bool, blockFinish: Bool
    private var startGate: CheckedContinuation<Void, Never>?
    private var finishGate: CheckedContinuation<Void, Never>?
    private var output: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?
    private(set) var isStarting = false
    private(set) var isFinishing = false
    init(text: String, blockStart: Bool = false, blockFinish: Bool = false) {
        self.text = text; self.blockStart = blockStart; self.blockFinish = blockFinish
    }
    func preferredInputFormat() async -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)
    }
    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        isStarting = true
        if blockStart { await withCheckedContinuation { startGate = $0 } }
        let (stream, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
        output = continuation
        return stream
    }
    func feed(_ chunk: AudioChunk) async {}
    func finish() async {
        isFinishing = true
        if blockFinish { await withCheckedContinuation { finishGate = $0 } }
        output?.yield(TranscriptionChunk(text: text, isFinal: true))
        output?.finish()
    }
    func cancel() async { output?.finish() }
    func releaseStart() { startGate?.resume(); startGate = nil }
    func releaseFinish() { finishGate?.resume(); finishGate = nil }
}

private actor SuspendedFormatter: TextFormatter {
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false
    func format(_ raw: String) async -> String {
        isWaiting = true
        await withCheckedContinuation { gate = $0 }
        return raw
    }
    func release() { gate?.resume(); gate = nil }
}
