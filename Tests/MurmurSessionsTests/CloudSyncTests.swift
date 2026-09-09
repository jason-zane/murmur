import Foundation
import MurmurSessions
import Testing

struct CloudSyncTests {
    @Test func offlineSyncDecisionPreservesConcurrentEditsAndLocalRemoval() {
        let previous = CloudSyncEntry(version: 4, fingerprint: "old")
        #expect(CloudSyncAction.decide(localFingerprint: "new", previous: previous, remoteVersion: 4) == .upload(expectedVersion: 4))
        #expect(CloudSyncAction.decide(localFingerprint: "old", previous: previous, remoteVersion: 5) == .download)
        #expect(CloudSyncAction.decide(localFingerprint: "new", previous: previous, remoteVersion: 5) == .conflict)
        #expect(CloudSyncAction.decide(localFingerprint: nil, previous: previous, remoteVersion: 4) == .keepLocalRemoval)
        #expect(CloudSyncAction.decide(localFingerprint: "new", previous: nil, remoteVersion: nil) == .upload(expectedVersion: 0))
        #expect(CloudSyncAction.decide(localFingerprint: "old", previous: previous, remoteVersion: 4) == .unchanged)
        let removed = CloudSyncEntry(version: 4, fingerprint: "old", removedLocally: true)
        #expect(CloudSyncAction.decide(localFingerprint: "restored", previous: removed, remoteVersion: 4) == .upload(expectedVersion: 4))
    }
    @Test func cloudImportPreservesRevisionDraftAndConflictingLocalDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(root: root)
        let session = try store.createNote(title: "Planning")
        try store.saveNote("Local note", for: session.id)
        try store.saveEditingDraft("Unfinished private thought", baseVersion: 1, for: session.id)
        let original = try #require(try store.cloudDocument(for: session.id))
        var remote = original; remote.note = "Cloud note"; remote.session.title = "Remote planning"
        let conflictID = try #require(try store.importCloudDocument(remote, expectedLocalFingerprint: original.fingerprint, preserveConflict: true))
        #expect(store.note(for: session.id) == "Cloud note")
        #expect(store.note(for: conflictID) == "Local note")
        #expect(store.noteRevisions(for: session.id).contains { $0.text == "Local note" })
        #expect(store.editingDraft(for: session.id)?.text == "Unfinished private thought")
        let payload = String(data: try CloudCoding.encoder.encode(store.cloudDocument(for: session.id)), encoding: .utf8)!
        #expect(!payload.contains("Unfinished private thought"))
        #expect(throws: CloudImportError.self) {
            try store.importCloudDocument(original, expectedLocalFingerprint: original.fingerprint)
        }
        #expect(store.note(for: session.id) == "Cloud note")
    }
    @Test func cloudImportIsCoherentAndCannotReplaceAnActiveRecording() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(root: root)
        var session = MeetingSession(id: "cloud-note", title: "From web", startedAt: Date(), state: .noted, engine: "Notes")
        let cloud = CloudDocument(session: session, transcript: [], bullets: [], note: "Synced text")
        _ = try store.importCloudDocument(cloud, expectedLocalFingerprint: nil)
        #expect(try store.cloudDocument(for: session.id)?.fingerprint == cloud.fingerprint)
        session.state = .recording; try store.save(session)
        #expect(throws: SessionStoreError.self) { try store.importCloudDocument(cloud, expectedLocalFingerprint: nil) }
        #expect(store.session(id: session.id)?.state == .recording)
    }
    @Test func cloudDatesAcceptBothNativeAndWebTimestamps() throws {
        let json = Data("\"2026-09-09T00:00:00.123Z\"".utf8)
        let date = try CloudCoding.decoder.decode(Date.self, from: json)
        #expect(date.timeIntervalSince1970 > 0)
        let encoded = try CloudCoding.encoder.encode(date)
        #expect(try CloudCoding.decoder.decode(Date.self, from: encoded).timeIntervalSince1970.rounded() == date.timeIntervalSince1970.rounded())
    }
}
