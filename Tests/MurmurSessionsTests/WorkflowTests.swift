import Foundation
import Testing
@testable import MurmurSessions

private final class Fixture {
    let store = SessionStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("murmur-workflow-\(UUID())"))
    deinit { try? FileManager.default.removeItem(at: store.root) }
}

@Suite struct WorkflowTests {
    @Test func editorDraftSurvivesConflictsAndIsExcludedFromExport() throws {
        let fixture = Fixture(), store = fixture.store
        let s = try store.createNote()
        try store.saveNote("Saved note", for: s.id, expectedVersion: 0)
        try store.saveEditingDraft("Unfinished edit", baseVersion: 1, for: s.id)
        try store.saveNote("External summary", for: s.id, expectedVersion: 1)
        let reopened = SessionStore(root: store.root)
        #expect(reopened.editingDraft(for: s.id) == EditingDraft(text: "Unfinished edit", baseVersion: 1))
        #expect(reopened.note(for: s.id) == "External summary")
        #expect(!reopened.markdown(for: s.id).contains("Unfinished edit"))
        try reopened.clearEditingDraft(for: s.id, matching: "Different draft")
        #expect(reopened.editingDraft(for: s.id) != nil)
        try reopened.clearEditingDraft(for: s.id, matching: "Unfinished edit")
        #expect(reopened.editingDraft(for: s.id) == nil)
    }
    @Test func delayedCallAudioKeepsItsMeetingTimestamp() {
        let timeline = CaptureTimeline(), start = Date()
        timeline.begin(at: start)
        timeline.observe(.you, at: start.addingTimeInterval(0.1))
        timeline.observe(.call, at: start.addingTimeInterval(45))
        timeline.observe(.call, at: start.addingTimeInterval(46))
        #expect(abs(timeline.offset(for: .you) - 0.1) < 0.001)
        #expect(timeline.offset(for: .call) == 45)
    }

    @Test func deadlinesAndCancellationReturnWithoutWaitingForWork() async throws {
        let start = ContinuousClock.now
        do {
            _ = try await AsyncDeadline.run(for: .milliseconds(10)) {
                try? await Task.sleep(for: .seconds(2))
                return "late"
            }
            Issue.record("Expected timeout")
        } catch is AsyncDeadline.TimedOut {}
        #expect(ContinuousClock.now - start < .seconds(1))
        let task = Task {
            try await AsyncDeadline.run(for: .seconds(10)) {
                try? await Task.sleep(for: .seconds(2))
                return "late"
            }
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {}
    }
    @Test func uniqueIDsAndLegacyManifests() throws {
        let date = Date()
        #expect(Set((0..<100).map { _ in MeetingSession.makeID(for: date) }).count == 100)
        let fixture = Fixture(), store = fixture.store
        let s = try store.createNote()
        let data = try Data(contentsOf: store.directory(for: s.id).appendingPathComponent("session.json"))
        #expect(!String(decoding: data, as: UTF8.self).contains("pinned"))
        #expect(store.session(id: s.id)?.isPinned == false)
    }

    @Test func revisionsArePreservedAndStaleWritesFail() throws {
        let fixture = Fixture(), store = fixture.store
        let s = try store.createNote()
        try store.saveNote("Original", for: s.id, expectedVersion: 0)
        try store.saveNote("My edit", for: s.id, expectedVersion: 1)
        #expect(throws: SessionStoreError.self) { try store.saveNote("Stale AI summary", for: s.id, expectedVersion: 1) }
        #expect(store.note(for: s.id) == "My edit")
        #expect(store.noteRevisions(for: s.id).map(\.text) == ["Original"])
        try store.saveNote("My edit", for: s.id, expectedVersion: 2)
        #expect(store.noteVersion(for: s.id) == 2)
        let updated = try store.update(id: s.id) { $0.title = "Renamed"; $0.pinned = true }
        #expect(updated.state == .noted)
        #expect(updated.isPinned)
    }

    @Test func concurrentNoteWritersKeepEveryRevision() async throws {
        let fixture = Fixture(), store = fixture.store
        let s = try store.createNote()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for n in 0..<12 { group.addTask { try store.saveNote("Version \(n)", for: s.id) } }
            try await group.waitForAll()
        }
        let all = store.noteRevisions(for: s.id).map(\.text) + [try #require(store.note(for: s.id))]
        #expect(all.count == 12)
        #expect(Set(all).count == 12)
    }

    @Test func traversalSymlinksAndDuplicateCreationAreRejected() throws {
        let fixture = Fixture(), store = fixture.store
        for id in ["../outside", "/tmp", "a/b", ".", "", "a%2fb"] {
            #expect(store.session(id: id) == nil)
            #expect(throws: SessionStoreError.self) { try store.saveNote("No", for: id) }
        }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-outside-\(UUID())")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: store.root.appendingPathComponent("linked"), withDestinationURL: outside)
        #expect(throws: SessionStoreError.self) { try store.create(MeetingSession(id: "linked", title: "No", startedAt: Date(), engine: "Notes")) }
        let s = try store.createNote()
        #expect(throws: SessionStoreError.self) { try store.create(s) }
    }

    @Test func searchesNotesAndTranscriptWithDateFilter() throws {
        let fixture = Fixture(), store = fixture.store
        let first = try store.createNote(title: "Roadmap")
        try store.saveNote("Discussed café expansion", for: first.id)
        let second = try store.createNote(title: "Planning")
        try store.saveBullets([NoteBullet(at: 12, text: "Migration owner")], for: second.id)
        #expect(store.findSessions("cafe").first?.location == "Notes")
        #expect(store.findSessions("migration").first?.timestamp == 12)
        #expect(store.findSessions("roadmap", since: Date().addingTimeInterval(60)).isEmpty)
        #expect(store.search("anything", limit: 0).isEmpty)
    }

    @Test func chunksPreserveEntireUnicodeMeeting() {
        let source = String(repeating: "[12:34] José: We chose option B. 👩🏽‍💻\n", count: 1_000)
        let chunks = MeetingNotes.chunks(source, maxCharacters: 200)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 200 })
        #expect(chunks.joined() == source)
        #expect(MeetingNotes.chunks(String(repeating: "X", count: 2_001), maxCharacters: 200).joined().count == 2_001)
        #expect(TimeFormat.clock(.infinity) == "0:00")
    }
}

@Suite struct AutomationTests {
    @Test func conferenceURLsAreValidated() {
        #expect(MeetingLink.conferenceURL(in: "Join https://meet.google.com/abc-defg-hij at ten")?.host == "meet.google.com")
        #expect(MeetingLink.conferenceURL(in: "https://us02web.zoom.us/j/12345?pwd=abc") != nil)
        #expect(MeetingLink.conferenceURL(in: "https://teams.microsoft.com/l/meetup-join/abc") != nil)
        for text in ["https://meet.google.com.evil.test/abc-defg-hij", "https://evil.test/meet.google.com", "file:///tmp/meeting", "https://zoom.us/signin", "https://meet.google.com/", "https://user@meet.google.com/abc-defg-hij"] {
            #expect(MeetingLink.conferenceURL(in: text) == nil)
        }
    }

    @Test func openingDoesNotReplayPastOrHandledOccurrences() throws {
        let now = Date(), url = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let upcoming = ScheduledMeeting(eventID: "recurring", start: now.addingTimeInterval(30), end: now.addingTimeInterval(3_600), url: url)
        let old = ScheduledMeeting(eventID: "old", start: now.addingTimeInterval(-120), end: now.addingTimeInterval(3_600), url: url)
        let next = ScheduledMeeting(eventID: "recurring", start: now.addingTimeInterval(86_400), end: now.addingTimeInterval(90_000), url: url)
        #expect(MeetingOpeningPolicy.due([old, upcoming, next], now: now, enabledSince: now, handled: []).map(\.id) == [upcoming.id])
        #expect(MeetingOpeningPolicy.due([upcoming], now: now, enabledSince: now, handled: [upcoming.id]).isEmpty)
        #expect(upcoming.id != next.id)
    }

    @Test func manualAndMutedCallsDoNotAutoStop() {
        var policy = CallEndPolicy()
        let now = Date()
        let results = [
            policy.shouldStop(bundleID: nil, hasInput: false, hasOutput: false, now: now, delay: 60),
            policy.shouldStop(bundleID: nil, hasInput: false, hasOutput: false, now: now.addingTimeInterval(600), delay: 60),
            policy.shouldStop(bundleID: "chrome", hasInput: false, hasOutput: false, now: now, delay: 60),
            policy.shouldStop(bundleID: "chrome", hasInput: false, hasOutput: true, now: now.addingTimeInterval(65), delay: 60),
            policy.shouldStop(bundleID: "chrome", hasInput: false, hasOutput: false, now: now.addingTimeInterval(70), delay: 60),
            policy.shouldStop(bundleID: "chrome", hasInput: false, hasOutput: false, now: now.addingTimeInterval(131), delay: 60),
        ]
        #expect(results == [false, false, false, false, false, true])
    }
}
