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

    @Test func captureGateRejectsLateAudioAfterPause() {
        let gate = MeetingCaptureGate()
        var delivered = 0
        gate.deliver { delivered += 1 }
        gate.close()
        gate.deliver { delivered += 1 }
        #expect(delivered == 1)
    }

    private func wait(until condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
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
    var engines: [MeetingTestTranscriber]
    private let savedSettings = (MeetingSettings.shared.autoSummarize, MeetingSettings.shared.speakerSeparation, MeetingSettings.shared.soundEnabled)
    lazy var controller = MeetingController(store: store, mic: mic, systemFactory: { [unowned self] in
        self.system = MeetingTestSystem()
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

private final class MeetingTestSystem: MeetingSystemAudioCapturing, Sendable {
    private let running = Mutex(false)
    var isRunning: Bool { running.withLock { $0 } }
    var outputDeviceChanged: Bool { false }
    func start(outputFormat: AVAudioFormat, onBuffer: @escaping @Sendable (AudioChunk) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void) throws { running.withLock { $0 = true } }
    func stop() { running.withLock { $0 = false } }
    func restart() throws {}
}

private actor MeetingTestTranscriber: MeetingTranscriber {
    var starting = false
    var finishing = false
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
    func feed(_ chunk: AudioChunk) async {}
    func emit(_ text: String) {
        events?.yield(.final(TranscriptSegment(start: 0, end: 0.01, source: source, text: text)))
    }
    func finish() async {
        finishing = true
        while blockFinish { try? await Task.sleep(for: .milliseconds(10)) }
        events?.finish()
    }
    func releaseStart() { blockStart = false }
    func releaseFinish() { blockFinish = false }
}
