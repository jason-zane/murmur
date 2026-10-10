import Foundation
import MurmurSessions
import Testing
@testable import Murmur

@MainActor @Suite(.serialized)
struct MailActionTests {
    @Test func repeatedActionsShareOnePendingBoundaryAndFailuresCanRetry() async throws {
        let transport = ActionTransport(), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox")
        let thread = try #require(store.threads.first)
        let first = Task { try await store.action("trash", thread: thread) }
        while transport.posts == 0 { await Task.yield() }
        #expect(store.isActing(on: thread))
        do { try await store.action("trash", thread: thread); Issue.record("Repeat should not submit") }
        catch let error as CloudHTTPError { #expect(error.status == 409) }
        try await first.value
        #expect(transport.posts == 1 && !store.isActing(on: thread))
        #expect(transport.lastAction == "trash" && transport.lastAccount == "fixture-account" && transport.lastID == "fixture-thread")
        transport.fail = true
        await #expect(throws: URLError.self) { try await store.action("restore", thread: thread) }
        #expect(!store.isActing(on: thread))
        transport.fail = false
        try await store.action("restore", thread: thread)
        #expect(transport.posts == 3 && transport.lastAction == "restore")
    }
    @Test func cancelledAndOldOwnerResponsesCannotReportSuccessOrWipeNewOwner() async throws {
        let transport = ActionTransport(), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox")
        let thread = try #require(store.threads.first)
        let pending = Task { try await store.action("trash", thread: thread) }
        while transport.posts == 0 { await Task.yield() }
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(!store.isActing(on: thread))
        let stale = Task { try await store.action("trash", thread: thread) }
        while transport.posts < 2 { await Task.yield() }
        transport.userID = "second-owner"
        await store.load(accountID: "", query: "in:inbox")
        await #expect(throws: CancellationError.self) { try await stale.value }
        #expect(store.accounts.count == 1 && store.threads.count == 1)
        transport.userID = nil
        await #expect(throws: CloudHTTPError.self) { try await store.action("restore", thread: thread) }
        #expect(transport.posts == 2)
    }
    @Test func sourceNotesSurviveRelaunchWithoutDuplicatingOrReplacingEdits() async throws {
        let transport = ActionTransport(), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailWorkspaceStore(transport: transport, root: root.appendingPathComponent("mail")), notes = SessionStore(root: root.appendingPathComponent("notes"))
        await store.load(accountID: "", query: "in:inbox")
        let thread = try #require(store.threads.first)
        await store.open(thread)
        let message = try #require(store.messages.first)
        let id = try store.createNote(from: message, thread: thread, notes: notes)
        try notes.saveNote("My reviewed wording", for: id)
        #expect(try store.createNote(from: message, thread: thread, notes: notes) == id)
        let restarted = MailWorkspaceStore(transport: transport, root: root.appendingPathComponent("mail"))
        await restarted.load(accountID: "", query: "in:inbox")
        await restarted.open(thread)
        #expect(try restarted.createNote(from: message, thread: thread, notes: notes) == id)
        #expect(notes.listSessions().count == 1)
        #expect(try String(contentsOf: notes.directory(for: id).appendingPathComponent("note.md"), encoding: .utf8) == "My reviewed wording")
        transport.userID = "second-owner"
        #expect(throws: CloudHTTPError.self) { try store.createNote(from: message, thread: thread, notes: notes) }
        transport.userID = nil
        #expect(throws: CloudHTTPError.self) { try store.createNote(from: message, thread: thread, notes: notes) }
    }
}

@MainActor private final class ActionTransport: CloudSyncTransport {
    var userID: String? = "first-owner"
    var posts = 0, fail = false
    var lastAction: String?, lastAccount: String?, lastID: String?
    func request(_ path: String, method: String, body: Data?) async throws -> Data {
        if method == "POST" {
            let payload = try JSONSerialization.jsonObject(with: body ?? Data()) as? [String: String]
            lastAction = payload?["action"]; lastAccount = payload?["account"]; lastID = payload?["id"]; posts += 1
            // Mimic a provider that has accepted work and may finish after cancellation.
            try? await Task.sleep(for: .milliseconds(150))
            if fail { throw URLError(.notConnectedToInternet) }
            return Data("{}".utf8)
        }
        let value: [String: Any]
        if path == "api/mail" { value = ["accounts": [["id": "fixture-account", "email": "alex@example.invalid"]], "outbox": []] }
        else if path.contains("thread=") { value = ["messages": [["id": "fixture-message", "thread_id": "fixture-thread", "subject": "Source note", "from": "priya@example.invalid", "to": "alex@example.invalid", "cc": "", "bcc": "", "date": "2026-10-02", "text": "Synthetic source", "html": "", "source_html": "", "reply_to": "", "message_id": "", "in_reply_to": "", "references": "", "attachments": []]]] }
        else { value = ["threads": [["id": "fixture-thread", "subject": "Source note", "from": "priya@example.invalid", "date": "2026-10-02", "snippet": "Synthetic source", "unread": true, "starred": false]]] }
        return try JSONSerialization.data(withJSONObject: value)
    }
}
