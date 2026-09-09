import AVFoundation
import AppKit
import Foundation
import MurmurSessions
import Observation

/// Runs one meeting: both captures, both transcribers, the session on disk, and the
/// notepad's bullets. One instance for the app; one session at a time.
///
/// Deliberately separate from `DictationController`. Dictation is seconds long, held in
/// memory, injected and forgotten, and protected by a watchdog against a lost key-up. A
/// meeting is hours long, appended to disk as it goes, kept forever, and must survive the
/// app dying mid-call. They share the audio and engine types and nothing else.
@MainActor
@Observable
final class MeetingController {
    enum State: Equatable {
        case idle
        case starting
        case recording
        case finalising

        var isActive: Bool { self == .starting || self == .recording }
    }

    /// What detection (or the user) knew when the session began.
    struct StartContext: Sendable {
        var title: String?
        var app: String?
        var bundleID: String?
        var calendarEvent: CalendarEvent?
        init(title: String? = nil, app: String? = nil, bundleID: String? = nil, calendarEvent: CalendarEvent? = nil) {
            self.title = title
            self.app = app
            self.bundleID = bundleID
            self.calendarEvent = calendarEvent
        }
    }

    private(set) var state: State = .idle
    private(set) var session: MeetingSession?
    private(set) var youLevel: Float = 0
    private(set) var callLevel: Float = 0
    /// Seconds since the session started. Drives every readout and stamps every bullet.
    private(set) var elapsed: TimeInterval = 0
    /// The most recent unfinalised text from either stream, for the optional live view.
    private(set) var livePartial = ""
    /// Finalised segments so far, in order.
    private(set) var liveSegments: [TranscriptSegment] = []
    /// Something went wrong but the session continues — e.g. system audio unavailable.
    private(set) var warning: String?
    private(set) var lastError: String?
    /// Set when a session finishes, so the Library can select it.
    private(set) var lastFinishedSessionID: String?

    var bullets: [NoteBullet] = [] {
        didSet { scheduleBulletSave() }
    }

    let store = SessionStore()

    private let mic = AudioCapture()
    private let system = SystemAudioCapture()
    private var micTranscriber: (any MeetingTranscriber)?
    private var callTranscriber: (any MeetingTranscriber)?
    private var micContinuation: AsyncStream<AudioChunk>.Continuation?
    private var callContinuation: AsyncStream<AudioChunk>.Continuation?
    private var feedTasks: [Task<Void, Never>] = []
    private var consumeTasks: [Task<Void, Never>] = []
    private var clockTask: Task<Void, Never>?
    private var bulletSaveTask: Task<Void, Never>?
    private var finishDone = false
    private var startedAt: Date?
    private var systemAudioActive = false

    /// Ceiling on the finish path. An engine that never returns must not hold the session.
    private static let finishDeadline: Duration = .seconds(45)

    init() {
        let recovered = store.recoverInterrupted()
        if !recovered.isEmpty {
            Log.app.info("recovered \(recovered.count) interrupted meeting session(s)")
        }
    }

    var isRecording: Bool { state == .recording }

    // MARK: - Start

    func start(_ context: StartContext = StartContext()) {
        guard state == .idle else { return }
        state = .starting
        lastError = nil
        warning = nil
        livePartial = ""
        liveSegments = []
        bullets = []
        youLevel = 0
        callLevel = 0
        elapsed = 0

        Task { @MainActor in
            do {
                guard await Permissions.requestMicrophone() else {
                    throw StartError.microphoneDenied
                }

                let now = Date()
                let engineName = MeetingSettings.shared.engine.displayName
                let title = context.title
                    ?? context.calendarEvent?.title
                    ?? Self.defaultTitle(app: context.app, at: now)
                var manifest = MeetingSession(
                    id: MeetingSession.makeID(for: now),
                    title: title,
                    startedAt: now,
                    state: .recording,
                    app: context.app,
                    bundleID: context.bundleID,
                    calendarEventID: context.calendarEvent?.id,
                    attendees: context.calendarEvent?.attendees ?? [],
                    engine: engineName
                )
                try store.create(manifest)
                manifest.duration = 0
                session = manifest

                // Two transcribers, one per stream, so the far side never bleeds into yours.
                let micT = Self.makeTranscriber()
                let callT = Self.makeTranscriber()
                micTranscriber = micT
                callTranscriber = callT

                let micEvents = try await micT.start(source: .you, offset: 0)
                let callEvents = try await callT.start(source: .call, offset: 0)

                guard let micFormat = await micT.preferredInputFormat(),
                      let callFormat = await callT.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }

                let (micStream, micCont) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(256))
                let (callStream, callCont) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(256))
                micContinuation = micCont
                callContinuation = callCont

                feedTasks = [
                    Task.detached(priority: .userInitiated) { for await chunk in micStream { await micT.feed(chunk) } },
                    Task.detached(priority: .userInitiated) { for await chunk in callStream { await callT.feed(chunk) } },
                ]
                consumeTasks = [
                    Task { @MainActor [weak self] in for await event in micEvents { self?.handle(event) } },
                    Task { @MainActor [weak self] in for await event in callEvents { self?.handle(event) } },
                ]

                try mic.start(
                    outputFormat: micFormat,
                    onBuffer: { micCont.yield($0) },
                    onLevel: { [weak self] level in Task { @MainActor in self?.youLevel = level } }
                )

                do {
                    try system.start(
                        outputFormat: callFormat,
                        onBuffer: { callCont.yield($0) },
                        onLevel: { [weak self] level in Task { @MainActor in self?.callLevel = level } }
                    )
                    systemAudioActive = true
                } catch {
                    // Your side still records. Say so, loudly enough to be fixed.
                    systemAudioActive = false
                    warning = "Recording your side only — \(error.localizedDescription)"
                    Log.audio.error("system audio unavailable: \(error.localizedDescription)")
                }

                startedAt = now
                state = .recording
                startClock()
                if MeetingSettings.shared.soundEnabled { NSSound(named: "Tink")?.play() }
                Log.app.info("meeting started · \(manifest.id, privacy: .public) · \(title, privacy: .public)")
            } catch {
                lastError = error.localizedDescription
                Log.app.error("meeting start failed: \(error.localizedDescription)")
                await abandon()
            }
        }
    }

    // MARK: - Stop

    func stop() {
        guard state == .recording else {
            if state == .starting { Task { await abandon() } }
            return
        }
        state = .finalising
        mic.stop()
        system.stop()
        youLevel = 0
        callLevel = 0
        clockTask?.cancel()
        clockTask = nil

        Task { @MainActor in
            let drained = await finishWithDeadline()
            if !drained { Log.speech.error("meeting transcribers did not finish within the deadline") }
            await completeSession()
        }
    }

    /// Drop the current session entirely. Used only when a start fails.
    private func abandon() async {
        mic.stop()
        system.stop()
        micContinuation?.finish()
        callContinuation?.finish()
        micContinuation = nil
        callContinuation = nil
        feedTasks.forEach { $0.cancel() }
        consumeTasks.forEach { $0.cancel() }
        feedTasks = []
        consumeTasks = []
        clockTask?.cancel()
        clockTask = nil
        let micT = micTranscriber, callT = callTranscriber
        micTranscriber = nil
        callTranscriber = nil
        Task { await micT?.finish(); await callT?.finish() }
        if let session, liveSegments.isEmpty {
            try? store.delete(id: session.id)
        }
        session = nil
        state = .idle
    }

    private func finishWithDeadline() async -> Bool {
        finishDone = false
        micContinuation?.finish()
        callContinuation?.finish()
        micContinuation = nil
        callContinuation = nil

        let micT = micTranscriber, callT = callTranscriber
        let feeds = feedTasks
        let consumes = consumeTasks
        let finish = Task { @MainActor [weak self] in
            for task in feeds { await task.value }
            await micT?.finish()
            await callT?.finish()
            for task in consumes { await task.value }
            self?.finishDone = true
        }

        let deadline = ContinuousClock.now.advanced(by: Self.finishDeadline)
        while !finishDone, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if !finishDone {
            finish.cancel()
            consumes.forEach { $0.cancel() }
        }
        feedTasks = []
        consumeTasks = []
        micTranscriber = nil
        callTranscriber = nil
        return finishDone
    }

    private func completeSession() async {
        guard var manifest = session else {
            state = .idle
            return
        }
        bulletSaveTask?.cancel()
        try? store.saveBullets(bullets.filter { !$0.text.isEmpty }, for: manifest.id)

        let segments = store.transcript(for: manifest.id)
        manifest.state = .raw
        manifest.endedAt = Date()
        manifest.duration = startedAt.map { Date().timeIntervalSince($0) } ?? elapsed
        manifest.segmentCount = segments.count
        manifest.speakers = Array(Set(segments.compactMap(\.speaker))).sorted()
        try? store.save(manifest)

        lastFinishedSessionID = manifest.id
        Log.app.info("meeting finished · \(manifest.id, privacy: .public) · \(segments.count) segments · \(TimeFormat.clock(manifest.duration), privacy: .public)")
        if MeetingSettings.shared.soundEnabled { NSSound(named: "Pop")?.play() }

        session = nil
        startedAt = nil
        livePartial = ""
        state = .idle
    }

    // MARK: - While recording

    func rename(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var manifest = session, !trimmed.isEmpty, trimmed != manifest.title else { return }
        manifest.title = trimmed
        session = manifest
        try? store.save(manifest)
    }

    /// A fresh bullet stamped with where the meeting is right now.
    func makeBullet() -> NoteBullet {
        NoteBullet(at: elapsed, text: "")
    }

    private func handle(_ event: MeetingTranscriptEvent) {
        switch event {
        case .partial(let text):
            livePartial = text
        case .final(let segment):
            liveSegments.append(segment)
            livePartial = ""
            if let session {
                do { try store.append([segment], to: session.id) }
                catch { Log.app.error("transcript append failed: \(error.localizedDescription)") }
            }
        }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { @MainActor [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
                ticks += 1
                // Every ten seconds: keep the manifest's duration and count honest on disk, so
                // a crash leaves a session that already knows how long it was.
                if ticks % 40 == 0, var manifest = self.session {
                    manifest.duration = self.elapsed
                    manifest.segmentCount = self.liveSegments.count
                    self.session = manifest
                    try? self.store.save(manifest)
                    if self.systemAudioActive, self.system.outputDeviceChanged {
                        self.warning = "Output device changed — call audio may have stopped. Stop and start again to follow it."
                    }
                }
            }
        }
    }

    private func scheduleBulletSave() {
        guard let session else { return }
        bulletSaveTask?.cancel()
        let id = session.id
        let snapshot = bullets.filter { !$0.text.isEmpty }
        bulletSaveTask = Task { @MainActor [store] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? store.saveBullets(snapshot, for: id)
        }
    }

    // MARK: - Helpers

    private static func makeTranscriber() -> any MeetingTranscriber {
        // Parakeet is chosen only when its models are on disk; otherwise Apple, which needs
        // nothing downloaded. The setting is honoured, not trusted.
        switch MeetingSettings.shared.engine {
        case .parakeet where ParakeetModels.isDownloaded:
            return ParakeetMeetingTranscriber()
        default:
            return AppleMeetingTranscriber()
        }
    }

    private static func defaultTitle(app: String?, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE HH:mm"
        return "\(app ?? "Meeting") · \(formatter.string(from: date))"
    }

    private enum StartError: LocalizedError {
        case microphoneDenied
        var errorDescription: String? {
            "Microphone access is off. Enable it in System Settings ▸ Privacy & Security ▸ Microphone."
        }
    }
}
