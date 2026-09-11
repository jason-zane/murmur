import Foundation
import MurmurSessions
import Testing
@testable import Murmur

@MainActor
@Suite(.serialized)
struct CloudSyncWorkflowTests {
    @Test func rejectedCredentialsOfferSignInAndRecoveryKeepsLocalNotes() async throws {
        let fixture = try SyncFixture()
        defer { fixture.remove() }
        try fixture.note("kept-locally", text: "Saved before reconnecting")
        let remote = MemorySyncTransport()
        remote.beforeRequest = { _, _ in throw CloudHTTPError(status: 401, message: "Sign in required") }
        let sync = CloudSync(store: fixture.store, transport: remote, agendaChanged: {})

        await sync.sync()
        #expect(sync.requiresSignIn && sync.needsAttention)
        #expect(sync.state == .signInRequired)
        #expect(fixture.store.note(for: "kept-locally") == "Saved before reconnecting")

        remote.beforeRequest = nil
        await sync.sync()
        #expect(!sync.requiresSignIn && !sync.needsAttention)
        #expect(remote.rows["kept-locally"]?.document.note == "Saved before reconnecting")
    }

    @Test func rejectedNoteDoesNotBlockOtherNotesOrCalendarAndRetriesLater() async throws {
        let fixture = try SyncFixture()
        defer { fixture.remove() }
        try fixture.note("a-rejected", text: "Kept locally")
        try fixture.note("b-ready", text: "Ready to sync")
        let remote = MemorySyncTransport()
        remote.rejected["a-rejected"] = CloudHTTPError(status: 413, message: "This meeting is too large to sync.")
        let sync = CloudSync(store: fixture.store, transport: remote, agendaChanged: {})

        await sync.sync()

        #expect(remote.rows["b-ready"]?.document.note == "Ready to sync")
        #expect(remote.rows["a-rejected"] == nil)
        #expect(fixture.store.note(for: "a-rejected") == "Kept locally")
        #expect(sync.issues.map(\.id) == ["a-rejected"])
        #expect(sync.calendarConnected && sync.meetings.count == 1)
        #expect(sync.calendarEmail == "fixture@example.invalid")
        #expect(sync.needsAttention && sync.lastSyncedAt == nil)
        #expect(sync.state == .attention(1))

        remote.rejected = [:]
        await sync.sync()

        #expect(remote.rows["a-rejected"]?.document.note == "Kept locally")
        #expect(remote.uploads.filter { $0 == "b-ready" }.count == 1)
        #expect(sync.issues.isEmpty && !sync.needsAttention)
        #expect(sync.lastSyncedAt != nil)
        #expect(sync.state == .upToDate(sync.lastSyncedAt))
    }

    @Test func uploadRaceRecoversBothDocumentsInTheSamePass() async throws {
        let fixture = try SyncFixture()
        defer { fixture.remove() }
        try fixture.note("shared-note", text: "Original")
        let remote = MemorySyncTransport()
        let sync = CloudSync(store: fixture.store, transport: remote, agendaChanged: {})
        await sync.sync()
        try fixture.store.saveNote("My offline edit", for: "shared-note")
        remote.beforeRequest = { path, method in
            guard path == "api/sessions", method == "POST" else { return }
            remote.beforeRequest = nil
            var row = try #require(remote.rows["shared-note"])
            row.version += 1
            row.document.note = "Saved on another device"
            row.document.transcript = [TranscriptSegment(start: 0, end: 4, source: .call, speaker: "Maya", text: "The corrected source.")]
            remote.rows[row.id] = row
        }

        await sync.sync()

        #expect(sync.issues.isEmpty && sync.conflictCount == 1)
        #expect(fixture.store.note(for: "shared-note") == "Saved on another device")
        #expect(fixture.store.transcript(for: "shared-note").first?.text == "The corrected source.")
        let copy = try #require(fixture.store.listSessions().first { $0.id != "shared-note" })
        #expect(copy.title.hasSuffix("(copy from this Mac)"))
        #expect(fixture.store.note(for: copy.id) == "My offline edit")
        #expect(fixture.store.noteRevisions(for: "shared-note").contains { $0.text == "My offline edit" })
        #expect(remote.rows["shared-note"]?.version == 2)
    }

    @Test func editWhileUploadIsInFlightIsSentOnNextPass() async throws {
        let fixture = try SyncFixture()
        defer { fixture.remove() }
        try fixture.note("changing-note", text: "Snapshot being uploaded")
        let remote = MemorySyncTransport()
        remote.afterResponse = { path, method in
            guard path == "api/sessions", method == "POST" else { return }
            remote.afterResponse = nil
            try fixture.store.saveNote("Typing continued during upload", for: "changing-note")
        }
        let sync = CloudSync(store: fixture.store, transport: remote, agendaChanged: {})

        await sync.sync()
        #expect(remote.rows["changing-note"]?.document.note == "Snapshot being uploaded")
        #expect(fixture.store.note(for: "changing-note") == "Typing continued during upload")
        await sync.sync()

        #expect(remote.rows["changing-note"]?.document.note == "Typing continued during upload")
        #expect(remote.rows["changing-note"]?.version == 2)
        #expect(fixture.store.listSessions().count == 1)
    }

    @Test func signOutDiscardsACompletedDownloadAndDoesNotRestoreCalendarOrStatus() async throws {
        let fixture = try SyncFixture()
        defer { fixture.remove() }
        let remote = MemorySyncTransport()
        remote.rows["from-cloud"] = .init(id: "from-cloud", version: 1, document: SyncFixture.document("from-cloud", text: "Must not import after sign-out"))
        let sync = CloudSync(store: fixture.store, transport: remote, agendaChanged: {})
        remote.afterResponse = { path, _ in
            guard path == "api/sessions/from-cloud" else { return }
            sync.stop()
            remote.userID = nil
        }

        await sync.sync()

        #expect(fixture.store.session(id: "from-cloud") == nil)
        #expect(sync.meetings.isEmpty && !sync.calendarConnected)
        #expect(sync.calendarEmail == nil && sync.calendarError == nil)
        #expect(sync.message == nil && sync.lastSyncedAt == nil && !sync.needsAttention)
        #expect(!sync.isSyncing)
        #expect(sync.state == .off)
    }

    @Test func stoppingManualSyncInvalidatesItsResponseEvenBeforeCredentialsAreRemoved() async throws {
        let fixture = try SyncFixture()
        defer { fixture.remove() }
        let remote = MemorySyncTransport()
        let sync = CloudSync(store: fixture.store, transport: remote, agendaChanged: {})
        remote.afterResponse = { _, _ in sync.stop() }

        await sync.sync()

        #expect(remote.userID != nil)
        #expect(remote.paths == ["api/calendar"])
        #expect(sync.meetings.isEmpty && !sync.calendarConnected && sync.message == nil)
    }

    @Test func bookedMeetingsCarryGuestContextAndOnlyBusyTimesAreShared() async throws {
        let fixture = try SyncFixture()
        defer { fixture.remove() }
        let remote = MemorySyncTransport()
        remote.bookingEnabled = true
        remote.booking = CloudBooking(id: "booking-1", event_type: "Intro call", template: "oneOnOne", guest_name: "Ada Guest",
                                      guest_email: "ada@example.invalid", answers: [.init(question: "What would you like to cover?", answer: "Pricing")])
        let start = Date().addingTimeInterval(3_600)
        remote.localBusy = [DateInterval(start: start, duration: 1_800)]
        let sync = CloudSync(store: fixture.store, transport: remote, agendaChanged: {}, busyTimes: { remote.localBusy })

        await sync.sync()
        #expect(sync.meetings.first?.booking?.guest_name == "Ada Guest")
        #expect(sync.meetings.first?.booking?.answers.first?.answer == "Pricing")
        #expect(remote.busyUploads == [[ISO8601DateFormatter().string(from: start)]])

        // Turning sharing off clears what this Mac shared, once.
        remote.localBusy = nil
        await sync.sync()
        await sync.sync()
        #expect(remote.busyUploads.count == 2 && remote.busyUploads.last == [])
    }

    @Test func offlineRestartLoadsOnlyTheLinkedAccountsCachedAgenda() async throws {
        let fixture = try SyncFixture()
        defer { fixture.remove() }
        try fixture.note("offline-note", text: "Saved here")
        let remote = MemorySyncTransport()
        await CloudSync(store: fixture.store, transport: remote, agendaChanged: {}).sync()
        remote.networkError = URLError(.notConnectedToInternet)
        let restarted = CloudSync(store: fixture.store, transport: remote, agendaChanged: {})

        await restarted.sync()

        #expect(restarted.meetings.count == 1 && restarted.calendarConnected)
        #expect(restarted.needsAttention && restarted.message?.contains("offline") == true)
        #expect(restarted.state == .offline)
        #expect(fixture.store.note(for: "offline-note") == "Saved here")
        remote.userID = "another-account"
        remote.paths = []
        let anotherAccount = CloudSync(store: fixture.store, transport: remote, agendaChanged: {})
        await anotherAccount.sync()
        #expect(anotherAccount.meetings.isEmpty && !anotherAccount.calendarConnected)
        #expect(anotherAccount.message?.contains("different Voice Notes account") == true)
        #expect(anotherAccount.state == .signInRequired)
        #expect(remote.paths.isEmpty)
    }

    @Test func mismatchedRemoteIdentityCannotWriteAnotherNoteOrBlockTheLibrary() async throws {
        let fixture = try SyncFixture()
        defer { fixture.remove() }
        let remote = MemorySyncTransport()
        remote.rows["a-invalid"] = .init(id: "a-invalid", version: 1, document: SyncFixture.document("wrong-target", text: "Wrong response"))
        remote.rows["b-valid"] = .init(id: "b-valid", version: 1, document: SyncFixture.document("b-valid", text: "Valid response"))
        let sync = CloudSync(store: fixture.store, transport: remote, agendaChanged: {})

        await sync.sync()

        #expect(fixture.store.session(id: "wrong-target") == nil)
        #expect(fixture.store.session(id: "a-invalid") == nil)
        #expect(fixture.store.note(for: "b-valid") == "Valid response")
        #expect(sync.issues.map(\.id) == ["a-invalid"])
    }
}

private struct SyncFixture {
    let root: URL
    let store: SessionStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-sync-workflow-\(UUID())")
        store = SessionStore(root: root.appendingPathComponent("sessions"))
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
    }
    func note(_ id: String, text: String) throws {
        try store.create(Self.document(id, text: text).session)
        try store.saveNote(text, for: id)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    static func document(_ id: String, text: String) -> CloudDocument {
        .init(session: MeetingSession(id: id, title: id, startedAt: Date(timeIntervalSince1970: 1_780_000_000), state: .noted, engine: "Notes"), transcript: [], bullets: [], note: text)
    }
}

@MainActor
private final class MemorySyncTransport: CloudSyncTransport {
    struct Row: Codable {
        var id: String
        var version: Int
        var deleted_at: String? = nil
        var document: CloudDocument
    }
    private struct Upload: Decodable { let document: CloudDocument; let expectedVersion: Int }
    private struct BusyUpload: Decodable {
        struct Block: Decodable { let start: String; let end: String }
        let blocks: [Block]
    }
    private struct Index: Encodable {
        let sessions: [Row]
        let nextOffset: Int? = nil
    }
    private struct Agenda: Encodable {
        let events: [CloudMeeting]
        let connection = Connection()
        var bookingEnabled: Bool? = nil
        struct Connection: Encodable { let email = "fixture@example.invalid" }
    }
    var userID: String? = "fixture-account"
    var rows: [String: Row] = [:]
    var uploads: [String] = []
    var paths: [String] = []
    var rejected: [String: CloudHTTPError] = [:]
    var networkError: URLError?
    var beforeRequest: ((String, String) throws -> Void)?
    var afterResponse: ((String, String) throws -> Void)?
    var bookingEnabled: Bool?
    var booking: CloudBooking?
    var localBusy: [DateInterval]?
    var busyUploads: [[String]] = []

    func request(_ path: String, method: String, body: Data?) async throws -> Data {
        paths.append(path)
        if let networkError { throw networkError }
        try beforeRequest?(path, method)
        let data: Data
        if path == "api/calendar" {
            data = try CloudCoding.encoder.encode(Agenda(events: [.init(id: "scheduled", title: "Fixture meeting", starts_at: Date().addingTimeInterval(600), ends_at: Date().addingTimeInterval(2_400), meeting_url: nil, attendees: [], booking: booking)], bookingEnabled: bookingEnabled))
        } else if path.hasPrefix("api/sync?") {
            data = try CloudCoding.encoder.encode(Index(sessions: rows.values.sorted { $0.id < $1.id }))
        } else if path.hasPrefix("api/sessions/"), method == "GET" {
            let id = String(path.dropFirst("api/sessions/".count))
            guard let row = rows[id] else { throw CloudHTTPError(status: 404, message: "Missing fixture") }
            data = try CloudCoding.encoder.encode(row)
        } else if path == "api/sessions", method == "POST" {
            let upload = try CloudCoding.decoder.decode(Upload.self, from: try #require(body))
            let id = upload.document.session.id
            uploads.append(id)
            if let error = rejected[id] { throw error }
            let version = rows[id]?.version ?? 0
            guard version == upload.expectedVersion else { throw CloudHTTPError(status: 409, message: "Concurrent fixture edit") }
            let row = Row(id: id, version: version + 1, document: upload.document)
            rows[id] = row
            data = try CloudCoding.encoder.encode(row)
        } else if path == "api/calendar/device-busy", method == "PUT" {
            let upload = try JSONDecoder().decode(BusyUpload.self, from: try #require(body))
            busyUploads.append(upload.blocks.map(\.start))
            data = Data(#"{"shared":\#(upload.blocks.count)}"#.utf8)
        } else { throw CloudHTTPError(status: 404, message: "Unexpected fixture request") }
        try afterResponse?(path, method)
        return data
    }
}
