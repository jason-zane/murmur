import Foundation
import Testing
@testable import MurmurSessions

@Suite struct SessionStoreTests {
    private func makeStore() throws -> SessionStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return SessionStore(root: root)
    }

    @Test func createAppendAndReadBack() throws {
        let store = try makeStore()
        let id = MeetingSession.makeID(for: Date(timeIntervalSince1970: 1_800_000_000))
        var session = MeetingSession(id: id, title: "Roadmap", startedAt: Date(), engine: "Apple")
        try store.create(session)

        try store.append([
            TranscriptSegment(start: 0, end: 2.5, source: .you, text: "So on pricing"),
            TranscriptSegment(start: 3, end: 6, source: .call, text: "Annual only"),
        ], to: id)
        try store.append([TranscriptSegment(start: 7, end: 9, source: .call, text: "Monthly is where we bleed")], to: id)

        let segments = store.transcript(for: id)
        #expect(segments.count == 3)
        #expect(segments.map(\.text) == ["So on pricing", "Annual only", "Monthly is where we bleed"])

        session.state = .raw
        session.segmentCount = 3
        try store.save(session)
        #expect(store.session(id: id)?.state == .raw)
        #expect(store.listSessions().count == 1)
    }

    @Test func notesAreRevisioned() throws {
        let store = try makeStore()
        let id = MeetingSession.makeID()
        try store.create(MeetingSession(id: id, title: "T", startedAt: Date(), state: .raw, engine: "Apple"))

        try store.saveNote("first", for: id)
        try store.saveNote("second", for: id)

        #expect(store.note(for: id) == "second")
        #expect(store.noteRevisionCount(for: id) == 1)
        #expect(store.noteVersion(for: id) == 2)
        #expect(store.session(id: id)?.state == .noted)
    }

    @Test func interruptedSessionsRecover() throws {
        let store = try makeStore()
        let id = MeetingSession.makeID()
        try store.create(MeetingSession(id: id, title: "Crashed", startedAt: Date(), state: .recording, engine: "Apple"))
        try store.append([TranscriptSegment(start: 0, end: 42, source: .call, text: "…")], to: id)

        let recovered = store.recoverInterrupted()
        #expect(recovered.count == 1)
        #expect(recovered[0].state == .raw)
        #expect(recovered[0].duration == 42)
        #expect(recovered[0].segmentCount == 1)
    }

    @Test func searchReturnsContext() throws {
        let store = try makeStore()
        let id = MeetingSession.makeID()
        try store.create(MeetingSession(id: id, title: "Search", startedAt: Date(), state: .raw, engine: "Apple"))
        try store.append([
            TranscriptSegment(start: 0, end: 5, source: .you, text: "Intro"),
            TranscriptSegment(start: 10, end: 15, source: .call, text: "Sarah owns the migration"),
            TranscriptSegment(start: 20, end: 25, source: .you, text: "Great"),
            TranscriptSegment(start: 120, end: 125, source: .you, text: "Far away"),
        ], to: id)

        let hits = store.search("MIGRATION")
        #expect(hits.count == 1)
        #expect(hits[0].segment.text == "Sarah owns the migration")
        #expect(hits[0].context.map(\.text) == ["Intro", "Sarah owns the migration", "Great"])
    }

    @Test func markdownExportContainsEverything() throws {
        let store = try makeStore()
        let id = MeetingSession.makeID()
        try store.create(MeetingSession(id: id, title: "Export", startedAt: Date(), state: .raw, engine: "Apple", duration: 65))
        try store.append([TranscriptSegment(start: 61, end: 64, source: .call, speaker: "Ben", text: "Annual only")], to: id)
        try store.saveBullets([NoteBullet(at: 60, text: "pricing")], for: id)

        let md = store.markdown(for: id)
        #expect(md.contains("# Export"))
        #expect(md.contains("- pricing  `1:00`"))
        #expect(md.contains("**1:01 Ben:** Annual only"))
    }

    @Test func clockFormatting() {
        #expect(TimeFormat.clock(0) == "0:00")
        #expect(TimeFormat.clock(65) == "1:05")
        #expect(TimeFormat.clock(3725) == "1:02:05")
    }
}
