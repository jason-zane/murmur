import AppKit
import SwiftUI
import AVFoundation
import Foundation
import MurmurSessions
import Synchronization
import Testing
@testable import Murmur

@MainActor
@Suite(.serialized)
struct MeetingRecordingTests {
    @Test func pauseResumeKeepsNoteAndAlignsTranscriptAcrossGap() async throws {
        let first = MeetingTestTranscriber(), second = MeetingTestTranscriber()
        let fixture = MeetingFixture(transcribers: [first, MeetingTestTranscriber(), second, MeetingTestTranscriber()])
        defer { fixture.cleanUp() }
        let c = fixture.controller
        c.start(.init(title: "Planning"))
        try await wait { c.isRecording && c.systemAudioActive }
        let id = try #require(c.session?.id)
        c.bullets = [NoteBullet(at: 0, text: "Keep this note")]
        await first.emit("Before pause")
        try await wait { c.liveSegments.count == 1 }
        c.pause()
        #expect(!fixture.mic.isRunning)
        try await wait { c.state == .paused && !fixture.system.isRunning }
        let pausedAt = Date()
        try await Task.sleep(for: .milliseconds(80))
        c.resume()
        try await wait { c.isRecording && c.systemAudioActive }
        await second.emit("After pause")
        try await wait { c.liveSegments.count == 2 }
        #expect(c.session?.id == id)
        #expect(c.session?.title == "Planning")
        #expect(c.bullets.first?.text == "Keep this note")
        let origin = try #require(c.session?.startedAt)
        #expect(c.liveSegments[1].start >= pausedAt.timeIntervalSince(origin))
        c.stop()
        try await wait { c.state == .idle }
        #expect(fixture.store.transcript(for: id).map(\.text) == ["Before pause", "After pause"])
        #expect(fixture.store.session(id: id)?.state == .raw)
    }

    @Test func stopWhilePauseDrainsSavesFinalWordsOnce() async throws {
        let engine = MeetingTestTranscriber(blockFinish: true)
        let fixture = MeetingFixture(transcribers: [engine, MeetingTestTranscriber()])
        defer { fixture.cleanUp() }
        let c = fixture.controller
        c.start()
        try await wait { c.isRecording }
        let id = try #require(c.session?.id)
        c.pause()
        try await wait { await engine.finishing }
        c.stop()
        c.stop()
        #expect(c.state == .finalising)
        await engine.emit("Last words")
        await engine.releaseFinish()
        try await wait { c.state == .idle }
        #expect(fixture.store.transcript(for: id).map(\.text) == ["Last words"])
    }

    @Test func stopDuringResumePreservesEarlierWordsAndPreventsLateCapture() async throws {
        let initial = MeetingTestTranscriber(), delayed = MeetingTestTranscriber(blockStart: true)
        let fixture = MeetingFixture(transcribers: [initial, MeetingTestTranscriber(), delayed, MeetingTestTranscriber()])
        defer { fixture.cleanUp() }
        let c = fixture.controller
        c.start()
        try await wait { c.isRecording }
        let id = try #require(c.session?.id)
        await initial.emit("Saved before pause")
        try await wait { c.liveSegments.count == 1 }
        c.pause()
        try await wait { c.state == .paused }
        c.resume()
        try await wait { await delayed.starting }
        c.stop()
        await delayed.releaseStart()
        try await wait { c.state == .idle }
        #expect(!fixture.mic.isRunning)
        #expect(fixture.store.transcript(for: id).map(\.text) == ["Saved before pause"])
    }

    @Test func failedResumeKeepsPausedNoteAvailableToStop() async throws {
        let fixture = MeetingFixture(transcribers: [MeetingTestTranscriber(), MeetingTestTranscriber()])
        defer { fixture.cleanUp() }
        let c = fixture.controller
        c.start()
        try await wait { c.isRecording }
        let id = try #require(c.session?.id)
        c.pause()
        try await wait { c.state == .paused }
        fixture.allowMicrophone = false
        c.resume()
        try await wait { c.state == .paused }
        #expect(c.session?.id == id)
        #expect(c.lastError != nil)
        c.stop()
        try await wait { c.state == .idle }
        #expect(fixture.store.session(id: id) != nil)
    }

    @Test func renderNarrowNotesWindowWithRecordingAndPausedControls() async throws {
        guard ProcessInfo.processInfo.environment["MURMUR_RENDER_MEETING_CONTROLS"] == "1" else { return }
        let fixture = MeetingFixture(transcribers: [MeetingTestTranscriber(), MeetingTestTranscriber()])
        defer { fixture.cleanUp() }
        let c = fixture.controller
        c.start(.init(title: "Weekly planning"))
        try await wait { c.isRecording && c.systemAudioActive }
        for label in ["recording", "paused"] {
            if label == "paused" {
                c.pause()
                try await wait { c.state == .paused }
            }
            let view = NSHostingView(rootView: NotepadView(controller: c, onRecord: {}))
            view.frame = NSRect(x: 0, y: 0, width: DS.Notepad.minWidth, height: DS.Notepad.minHeight)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/murmur-controls-\(label).png"))
        }
        c.stop()
        try await wait { c.state == .idle }
    }

    @Test(arguments: [false, true])
    func warnsWhenOnlyMicrophoneSpeechWasSaved(hasCallSpeech: Bool) async throws {
        let mic = MeetingTestTranscriber(), call = MeetingTestTranscriber()
        let fixture = MeetingFixture(transcribers: [mic, call])
        defer { fixture.cleanUp() }
        let c = fixture.controller
        c.start(.init(title: "Audio check", app: "Teams", bundleID: "com.google.Chrome"))
        try await wait { c.isRecording && c.systemAudioActive }
        await mic.emit("My side")
        if hasCallSpeech { await call.emit("The other side") }
        try await wait { c.liveSegments.count == (hasCallSpeech ? 2 : 1) }
        c.stop()
        try await wait { c.state == .idle }
        #expect((c.lastError != nil) == !hasCallSpeech)
    }

    @Test func microphonePermissionDeniedStartsNeitherInput() async throws {
        let f = MeetingFixture(transcribers: [])
        defer { f.cleanUp() }
        f.allowMicrophone = false
        f.controller.start()
        try await wait { f.controller.state == .idle }
        #expect(f.controller.lastError != nil)
        #expect(!f.mic.isRunning && !f.system.isRunning)
        #expect(f.store.listSessions().isEmpty)
    }

    @Test func callCapturePermissionFailureKeepsMicrophoneAndWarns() async throws {
        let mic = MeetingTestTranscriber()
        let f = MeetingFixture(transcribers: [mic, MeetingTestTranscriber()])
        defer { f.cleanUp() }
        f.configureSystem = { $0.failStart = true }
        let c = f.controller
        c.start(.init(app: "Teams"))
        try await wait { c.warning != nil }
        #expect(c.isRecording && f.mic.isRunning && !c.systemAudioActive)
        await mic.emit("Microphone remains usable")
        try await wait { c.liveSegments.count == 1 }
        let id = try #require(c.session?.id)
        c.stop()
        try await wait { c.state == .idle }
        #expect(f.store.transcript(for: id).count == 1)
        #expect(c.lastError != nil)
    }

    @Test func lateTapStartupAfterStopCannotLeakIntoTheNextNote() async throws {
        let oldCall = MeetingTestTranscriber()
        let f = MeetingFixture(transcribers: [MeetingTestTranscriber(), oldCall,
                                               MeetingTestTranscriber(), MeetingTestTranscriber()])
        defer { f.cleanUp() }
        f.configureSystem = { $0.blockStart = true }
        let c = f.controller
        c.start()
        let old = f.system
        defer { old.releaseStart() }
        try await wait { old.starting }
        c.stop()
        try await wait { c.state == .idle }
        f.configureSystem = { _ in }
        c.start()
        try await wait { c.isRecording && c.systemAudioActive }
        old.releaseStart()
        try await wait { old.startReturned && !old.isRunning }
        old.emitBuffer()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await oldCall.fedBuffers == 0)
        #expect(c.isRecording && c.systemAudioActive)
        c.stop()
        try await wait { c.state == .idle }
    }

    @Test(arguments: [false, true])
    func transcriberFailureIsVisibleEvenDuringFinalisation(duringFinish: Bool) async throws {
        let call = MeetingTestTranscriber(blockFinish: duringFinish)
        let f = MeetingFixture(transcribers: [MeetingTestTranscriber(), call])
        defer { f.cleanUp() }
        let c = f.controller
        c.start(.init(app: "Teams"))
        try await wait { c.isRecording }
        await call.emit("Earlier call words")
        try await wait { c.liveSegments.count == 1 }
        if duringFinish {
            c.stop()
            try await wait { await call.finishing }
        }
        await call.fail()
        try await wait { c.warning != nil }
        if duringFinish { await call.releaseFinish() } else { c.stop() }
        try await wait { c.state == .idle }
        #expect(c.lastError != nil)
    }

    @Test func unexpectedlyClosedCallTranscriberIsNotSilentlyAccepted() async throws {
        let call = MeetingTestTranscriber()
        let f = MeetingFixture(transcribers: [MeetingTestTranscriber(), call])
        defer { f.cleanUp() }
        let c = f.controller
        c.start()
        try await wait { c.isRecording }
        await call.closeEvents()
        try await wait { c.warning != nil }
        c.stop()
        try await wait { c.state == .idle }
        #expect(c.lastError != nil)
    }

    @Test(arguments: [false, true])
    func outputDeviceChangeReconnectsOrReportsFailure(failRestart: Bool) async throws {
        let f = MeetingFixture(transcribers: [MeetingTestTranscriber(), MeetingTestTranscriber()])
        defer { f.cleanUp() }
        let c = f.controller
        c.start()
        try await wait { c.isRecording && c.systemAudioActive }
        f.system.failRestart = failRestart
        f.system.changed = true
        try await wait(limit: .seconds(12)) { f.system.restartCount == 1 }
        try await wait { failRestart ? c.warning != nil : c.systemAudioActive }
        #expect(c.isRecording && f.mic.isRunning)
        #expect(c.systemAudioActive == !failRestart)
        c.stop()
        try await wait { c.state == .idle }
        if failRestart { #expect(c.lastError != nil) }
    }

    @Test func failedDiskSaveRetainsTranscriptForRetry() async throws {
        let call = MeetingTestTranscriber()
        let f = MeetingFixture(transcribers: [MeetingTestTranscriber(), call])
        defer { f.cleanUp() }
        let c = f.controller
        c.start()
        try await wait { c.isRecording }
        await call.emit("Words that must survive a save failure")
        try await wait { c.liveSegments.count == 1 }
        let id = try #require(c.session?.id)
        let backup = f.store.root.appendingPathExtension("backup")
        try FileManager.default.moveItem(at: f.store.root, to: backup)
        try Data("block writes".utf8).write(to: f.store.root)
        c.stop()
        try await wait { c.state == .saveFailed }
        #expect(c.liveSegments.count == 1)
        try FileManager.default.removeItem(at: f.store.root)
        try FileManager.default.moveItem(at: backup, to: f.store.root)
        c.retrySave()
        try await wait { c.state == .idle }
        #expect(f.store.transcript(for: id).first?.text == "Words that must survive a save failure")
    }

    @Test(arguments: [false, true])
    func hungTranscriberCannotPreventSavingEarlierWords(pauseFirst: Bool) async throws {
        let call = MeetingTestTranscriber(blockFinish: true)
        let f = MeetingFixture(transcribers: [MeetingTestTranscriber(), call])
        defer { f.cleanUp() }
        let c = f.controller
        c.start()
        try await wait { c.isRecording }
        await call.emit("Durable words")
        try await wait { c.liveSegments.count == 1 }
        let id = try #require(c.session?.id)
        if pauseFirst {
            c.pause()
            try await wait(limit: .seconds(23)) { c.state == .paused }
            await call.releaseFinish()
            f.engines = [MeetingTestTranscriber(), MeetingTestTranscriber()]
            c.resume()
            try await wait { c.isRecording }
        }
        c.stop()
        try await wait(limit: .seconds(23)) { c.state == .idle }
        #expect(c.lastError != nil)
        #expect(f.store.transcript(for: id).first?.text == "Durable words")
        await call.releaseFinish()
    }

    @Test func captureGateRejectsLateAudioAfterPause() {
        let gate = MeetingCaptureGate()
        var delivered = 0
        gate.deliver { delivered += 1 }
        gate.close()
        gate.deliver { delivered += 1 }
        #expect(delivered == 1)
    }

    private func wait(limit: Duration = .seconds(3), until condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await condition())
    }
}

@MainActor
private final class MeetingFixture {
    let store = SessionStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("meeting-controls-\(UUID())"))
    let mic = MeetingTestMic()
    var system = MeetingTestSystem()
    var allowMicrophone = true
    var configureSystem: (MeetingTestSystem) -> Void = { _ in }
    var engines: [MeetingTestTranscriber]
    private let savedSettings = (MeetingSettings.shared.autoSummarize, MeetingSettings.shared.speakerSeparation, MeetingSettings.shared.soundEnabled)
    lazy var controller = MeetingController(store: store, mic: mic, systemFactory: { [unowned self] in
        self.system = MeetingTestSystem()
        self.configureSystem(self.system)
        return self.system
    }, transcriberFactory: { [unowned self] in self.engines.removeFirst() }, requestMicrophone: { [unowned self] in self.allowMicrophone })

    init(transcribers: [MeetingTestTranscriber]) {
        engines = transcribers
        MeetingSettings.shared.autoSummarize = false
        MeetingSettings.shared.speakerSeparation = false
        MeetingSettings.shared.soundEnabled = false
    }

    func cleanUp() {
        MeetingSettings.shared.autoSummarize = savedSettings.0
        MeetingSettings.shared.speakerSeparation = savedSettings.1
        MeetingSettings.shared.soundEnabled = savedSettings.2
        try? FileManager.default.removeItem(at: store.root)
    }
}

private final class MeetingTestMic: DictationAudioCapturing, Sendable {
    private let running = Mutex(false)
    var isRunning: Bool { running.withLock { $0 } }
    func start(outputFormat: AVAudioFormat, onBuffer: @escaping @Sendable (AudioChunk) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void) async throws {
        running.withLock { $0 = true }
        let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1)!
        buffer.frameLength = 1
        onBuffer(AudioChunk(buffer: buffer))
    }
    func stop() { running.withLock { $0 = false } }
}

private final class MeetingTestSystem: MeetingSystemAudioCapturing, @unchecked Sendable {
    private struct State {
        var running = false
        var starting = false
        var returned = false
        var blockStart = false
        var failStart = false
        var failRestart = false
        var changed = false
        var restarts = 0
        var onBuffer: (@Sendable (AudioChunk) -> Void)?
        var format: AVAudioFormat?
    }
    private let state = Mutex(State())
    private let startGate = DispatchSemaphore(value: 0)
    var isRunning: Bool { state.withLock { $0.running } }
    var starting: Bool { state.withLock { $0.starting } }
    var startReturned: Bool { state.withLock { $0.returned } }
    var restartCount: Int { state.withLock { $0.restarts } }
    var outputDeviceChanged: Bool { changed }
    var blockStart: Bool {
        get { state.withLock { $0.blockStart } }
        set { state.withLock { $0.blockStart = newValue } }
    }
    var failStart: Bool {
        get { state.withLock { $0.failStart } }
        set { state.withLock { $0.failStart = newValue } }
    }
    var failRestart: Bool {
        get { state.withLock { $0.failRestart } }
        set { state.withLock { $0.failRestart = newValue } }
    }
    var changed: Bool {
        get { state.withLock { $0.changed } }
        set { state.withLock { $0.changed = newValue } }
    }
    func start(outputFormat: AVAudioFormat, onBuffer: @escaping @Sendable (AudioChunk) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void) throws {
        state.withLock { $0.starting = true; $0.onBuffer = onBuffer; $0.format = outputFormat }
        if blockStart { startGate.wait() }
        if failStart { throw CaptureError.couldNotStart }
        state.withLock { $0.running = true; $0.returned = true }
        emitBuffer()
    }
    func releaseStart() { startGate.signal() }
    func emitBuffer() {
        let (format, callback) = state.withLock { ($0.format, $0.onBuffer) }
        guard let format else { return }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        buffer.floatChannelData?[0][0] = 0
        callback?(AudioChunk(buffer: buffer))
    }
    func stop() { state.withLock { $0.running = false } }
    func restart() throws {
        state.withLock { $0.restarts += 1; $0.changed = false }
        if failRestart {
            state.withLock { $0.running = false }
            throw CaptureError.couldNotStart
        }
    }
}

private actor MeetingTestTranscriber: MeetingTranscriber {
    var starting = false
    var finishing = false
    var fedBuffers = 0
    var blockStart: Bool
    var blockFinish: Bool
    private var source: AudioStreamSource = .you
    private var events: AsyncStream<MeetingTranscriptEvent>.Continuation?
    init(blockStart: Bool = false, blockFinish: Bool = false) {
        self.blockStart = blockStart
        self.blockFinish = blockFinish
    }
    func preferredInputFormat() async -> AVAudioFormat? { AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1) }
    func start(source: AudioStreamSource, offset: TimeInterval) async throws -> AsyncStream<MeetingTranscriptEvent> {
        starting = true
        while blockStart { try await Task.sleep(for: .milliseconds(10)) }
        self.source = source
        let pair = AsyncStream<MeetingTranscriptEvent>.makeStream()
        events = pair.continuation
        return pair.stream
    }
    func feed(_ chunk: AudioChunk) async { fedBuffers += 1 }
    func emit(_ text: String) {
        events?.yield(.final(TranscriptSegment(start: 0, end: 0.01, source: source, text: text)))
    }
    func finish() async {
        finishing = true
        while blockFinish { try? await Task.sleep(for: .milliseconds(10)) }
        events?.finish()
    }
    func fail() { events?.yield(.failed(source, "Simulated speech-engine failure")) }
    func closeEvents() { events?.finish() }
    func releaseStart() { blockStart = false }
    func releaseFinish() { blockFinish = false }
}
