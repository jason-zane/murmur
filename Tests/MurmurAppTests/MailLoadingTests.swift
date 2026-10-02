import Foundation
import Testing
@testable import Murmur

@MainActor @Suite(.serialized)
struct MailLoadingTests {
    @Test func changingSenderPreservesWordingAndKeepsProviderIdentityInItsMailbox() {
        var source = MailDraft(accountID: "personal", userID: "owner")
        source.to = "recipient@example.invalid"; source.cc = "copy@example.invalid"; source.subject = "Reviewed wording"; source.text = "Keep these edits"; source.html = "<p>Keep formatting</p>"
        source.providerID = "gmail-personal-draft"; source.revision = "personal-revision"; source.threadID = "personal-thread"; source.replyID = "<original-message@example.invalid>"
        let switched = source.changingSender(to: "work")
        #expect(switched.accountID == "work" && switched.id != source.id && switched.operationID != source.operationID)
        #expect(switched.providerID == nil && switched.revision == nil && switched.threadID == nil)
        #expect(switched.to == source.to && switched.cc == source.cc && switched.subject == source.subject && switched.text == source.text && switched.html == source.html && switched.replyID == source.replyID)
        #expect(source.changingSender(to: "personal").id == source.id)
        let local = MailDraft(accountID: "personal", userID: "owner")
        #expect(local.changingSender(to: "work").id == local.id)
    }
    @Test func accountLoadsOverlapWithBoundedConcurrencyAndKeepPartialMail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = LoadingTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        let start = Date()
        await store.load(accountID: "", query: "in:inbox")
        print("Synthetic four-mailbox load (150 ms each): \(Date().timeIntervalSince(start)) s; peak concurrency \(transport.peak)")
        #expect(transport.peak == 3)
        #expect(store.threads.count == 4 && !store.loading)
        transport.failingAccount = "a2"; transport.round = 2
        await store.load(accountID: "", query: "in:inbox")
        #expect(store.threads.count == 4)
        #expect(store.threads.first(where: { $0.accountID == "a2" })?.subject == "Round 1")
        #expect(store.threads.filter { $0.accountID != "a2" }.allSatisfy { $0.subject == "Round 2" })
        #expect(store.notice?.contains("a2@example.invalid") == true)
    }
    @Test func cancelledLoadAndAccountChangeCannotApplyResponses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = LoadingTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        let task = Task { await store.load(accountID: "", query: "in:inbox") }
        while transport.active == 0 { await Task.yield() }
        task.cancel(); await task.value
        #expect(store.threads.isEmpty && !store.loading)
        let changed = Task { await store.load(accountID: "", query: "in:inbox") }
        while transport.active == 0 { await Task.yield() }
        transport.userID = nil
        await changed.value
        #expect(store.accounts.isEmpty && store.threads.isEmpty)
    }
    @Test func oldReaderResponseCannotReplaceNewConversationOrClearLoading() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = LoadingTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox")
        let first = try #require(store.threads.first { $0.accountID == "a1" }), second = try #require(store.threads.first { $0.accountID == "a2" })
        let old = Task { await store.open(first) }
        while transport.active == 0 { await Task.yield() }
        let newer = Task { await store.open(second) }
        await old.value
        #expect(store.readerLoading && store.messages.isEmpty)
        await newer.value
        #expect(!store.readerLoading && store.messages.first?.id == "a2")
        let leaving = Task { await store.open(first) }
        while transport.active == 0 { await Task.yield() }
        store.closeConversation()
        await leaving.value
        #expect(store.messages.isEmpty && !store.readerLoading)
    }
}

@MainActor private final class LoadingTransport: CloudSyncTransport {
    var userID: String? = "synthetic-owner"
    var active = 0, peak = 0, round = 1
    var failingAccount: String?
    func request(_ path: String, method: String, body: Data?) async throws -> Data {
        #expect(method == "GET")
        if path == "api/mail" {
            return try JSONSerialization.data(withJSONObject: ["accounts": (1...4).map { ["id": "a\($0)", "email": "a\($0)@example.invalid"] }, "outbox": []] as [String:Any])
        }
        let account = URLComponents(string: path)?.queryItems?.first { $0.name == "account" }?.value ?? ""
        active += 1; peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(path.contains("thread=") && account == "a2" ? 300 : 150))
        if account == failingAccount { throw URLError(.notConnectedToInternet) }
        if path.contains("thread=") {
            return try JSONSerialization.data(withJSONObject: ["messages": [["id": account, "thread_id": account, "subject": "Source", "from": "fixture@example.invalid", "to": "owner@example.invalid", "cc": "", "bcc": "", "date": "2026-10-02", "text": "Synthetic source", "html": "", "source_html": "", "reply_to": "", "message_id": "", "in_reply_to": "", "references": "", "attachments": []]]])
        }
        return try JSONSerialization.data(withJSONObject: ["threads": [["id": account, "subject": "Round \(round)", "from": "fixture@example.invalid", "date": "2026-10-02", "snippet": "Synthetic", "unread": false, "starred": false]], "next_page": NSNull()])
    }
}
