import Foundation
import Testing
@testable import Murmur

@MainActor @Suite(.serialized)
struct MailWorkspaceStoreTests {
    @Test func downloadedMailAndIndependentDraftsSurviveOfflineRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MailFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox")
        #expect(store.threads.count == 1)
        await store.open(try #require(store.threads.first))
        #expect(store.messages.first?.text == "Private fixture body")
        var first = MailDraft(accountID: "account", userID: "mail-owner"); first.subject = "First draft"
        var second = MailDraft(accountID: "account", userID: "mail-owner"); second.subject = "Another draft"
        try store.saveLocal(first); try store.saveLocal(second)
        transport.offline = true
        let restarted = MailWorkspaceStore(transport: transport, root: root)
        await restarted.load(accountID: "", query: "in:inbox")
        #expect(restarted.offline && restarted.drafts.count == 2 && restarted.threads.count == 1)
        await restarted.open(try #require(restarted.threads.first))
        #expect(restarted.messages.first?.text == "Private fixture body")
        transport.userID = "another-owner"
        await restarted.load(accountID: "", query: "in:inbox")
        #expect(restarted.accounts.isEmpty && restarted.drafts.isEmpty && restarted.threads.isEmpty)
        #expect(throws: CancellationError.self) { try restarted.saveLocal(first) }
    }
    @Test func olderBackendKeepsDraftsAndExplainsUpgrade() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MailFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox")
        var draft = MailDraft(accountID: "account", userID: "mail-owner"); draft.subject = "Keep this draft"
        try store.saveLocal(draft)
        transport.missingEndpoint = true
        await store.load(accountID: "", query: "in:inbox")
        #expect(store.drafts.first?.subject == "Keep this draft")
        #expect(store.threads.count == 1 && store.offline)
        #expect(store.notice?.contains("hosted workspace upgrade") == true)
    }
    @Test func interruptedQueueUsesTheSameOperationOnReconnect() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MailFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        var draft = MailDraft(accountID: "account", userID: "mail-owner"); draft.to = "recipient@example.invalid"; draft.text = "Approved message"
        transport.offline = true
        await #expect(throws: URLError.self) { try await store.queue(draft) }
        #expect(store.drafts.first?.queued == true)
        transport.offline = false
        await store.load(accountID: "", query: "in:inbox", metadataOnly: true)
        #expect(transport.operations == [draft.operationID, draft.operationID])
        #expect(store.drafts.isEmpty)
    }
    @Test func rejectedReconnectIsNotAutomaticallySentAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MailFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        let draft = MailDraft(accountID: "account", userID: "mail-owner")
        transport.offline = true
        await #expect(throws: URLError.self) { try await store.queue(draft) }
        transport.offline = false; transport.reject = true
        await store.load(accountID: "", query: "in:inbox", metadataOnly: true)
        #expect(store.drafts.first?.queued == false)
        await store.load(accountID: "", query: "in:inbox", metadataOnly: true)
        #expect(transport.operations.count == 2)
    }
    @Test func offlineUndoStopsResubmissionAndRetainsDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MailFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        let draft = MailDraft(accountID: "account", userID: "mail-owner")
        transport.offline = true
        await #expect(throws: URLError.self) { try await store.queue(draft) }
        await #expect(throws: URLError.self) { try await store.cancelLocalQueue(draft.id) }
        transport.offline = false
        await store.load(accountID: "", query: "in:inbox", metadataOnly: true)
        #expect(transport.operations.count == 1)
        #expect(store.drafts.first?.queued == false && store.drafts.first?.cancelRequested == nil)
        #expect(mailAddresses(#""Doe, Jane" <jane@example.invalid>, other@example.invalid"#).count == 2)
    }
    @Test func clearingDownloadsInvalidatesOutstandingResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MailFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox")
        transport.onResponse = { try? store.clearDownloaded() }
        await store.open(try #require(store.threads.first))
        #expect(store.messages.isEmpty && store.threads.isEmpty)
        transport.onResponse = nil; transport.offline = true
        let restarted = MailWorkspaceStore(transport: transport, root: root)
        await restarted.load(accountID: "", query: "in:inbox")
        #expect(restarted.threads.isEmpty)
    }
    @Test func newOfflineSearchUsesDownloadedFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MailFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox")
        transport.offline = true
        await store.load(accountID: "", query: "in:inbox Planning")
        #expect(store.offline && store.threads.first?.subject == "Planning")
    }
    @Test func gmailDraftKeepsFormattingRecipientsAndLocalRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MailFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox", metadataOnly: true)
        await store.loadProviderDrafts(accountID: "")
        let provider = try #require(store.providerDrafts.first)
        var draft = try await store.openProviderDraft(provider)
        #expect(draft.html == "<p>Formatted body</p>" && draft.revision == "revision-one")
        #expect(draft.bcc == "private@example.invalid")
        draft.subject = "Local unsynchronised change"; try store.saveLocal(draft)
        transport.offline = true
        let recovered = try await store.openProviderDraft(provider)
        #expect(recovered.subject == "Local unsynchronised change")
    }
    @Test func terminalProviderPageRemovesItsOldToken() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MailFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        transport.paged = true
        await store.load(accountID: "", query: "in:inbox")
        #expect(store.pages["account"] == "next")
        await store.load(accountID: "", query: "in:inbox", more: true)
        #expect(store.pages.isEmpty)
        await store.loadProviderDrafts(accountID: "")
        #expect(store.providerPages["account"] == "next")
        await store.loadProviderDrafts(accountID: "", more: true)
        #expect(store.providerPages.isEmpty)
    }
    @Test func signOutDuringFetchDoesNotRestorePrivateState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MailFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        transport.signOut = true
        await store.load(accountID: "", query: "in:inbox")
        #expect(store.accounts.isEmpty && store.threads.isEmpty && !store.loading)
    }
}
@MainActor private final class MailFixtureTransport: CloudSyncTransport {
    var userID: String? = "mail-owner"
    var offline = false
    var missingEndpoint = false
    var signOut = false
    var reject = false
    var paged = false
    var operations: [String] = []
    var onResponse: (() -> Void)? = nil
    func request(_ path: String, method: String, body: Data?) async throws -> Data {
        let data = try await response(path, method: method, body: body)
        if paged && !path.contains("page=") { return Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"next_page\":null", with: "\"next_page\":\"next\"").utf8) }
        return data
    }
    private func response(_ path: String, method: String, body: Data?) async throws -> Data {
        if missingEndpoint { throw CloudHTTPError(status: 404, message: "Not found") }
        if method == "POST", let body, let json = try JSONSerialization.jsonObject(with: body) as? [String: Any], let operation = json["operation_id"] as? String {
            operations.append(operation)
            if offline { throw URLError(.notConnectedToInternet) }
            if reject { throw CloudHTTPError(status: 400, message: "Choose a recipient.") }
            return Data(#"{"id":"queued","status":"queued"}"#.utf8)
        }
        if offline { throw URLError(.notConnectedToInternet) }
        if signOut { userID = nil }
        onResponse?()
        if path.contains("operation=") { return Data(#"{"operation":null}"#.utf8) }
        if path == "api/mail" { return Data(#"{"accounts":[{"id":"account","email":"owner@example.invalid"}],"outbox":[]}"#.utf8) }
        if path.contains("draft=") { return Data(#"{"id":"provider-draft","revision":"revision-one","message":{"id":"message","thread_id":"thread","subject":"Planning","from":"sender@example.invalid","to":"owner@example.invalid","cc":"","bcc":"private@example.invalid","date":"2026-09-30T00:00:00Z","text":"Private fixture body","html":"","source_html":"<p>Formatted body</p>","reply_to":"","message_id":"<message@example.invalid>","in_reply_to":"","references":"","attachments":[]},"attachments":[]}"#.utf8) }
        if path.contains("drafts=") { return Data(#"{"drafts":[{"id":"provider-draft","message":{"id":"message","thread_id":"thread","subject":"Planning","from":"sender@example.invalid","to":"owner@example.invalid","cc":"","bcc":"private@example.invalid","date":"2026-09-30T00:00:00Z","text":"Private fixture body","html":"","source_html":"<p>Formatted body</p>","reply_to":"","message_id":"<message@example.invalid>","in_reply_to":"","references":"","attachments":[]}}],"next_page":null}"#.utf8) }
        if path.contains("thread=") { return Data(#"{"messages":[{"id":"message","thread_id":"thread","subject":"Planning","from":"sender@example.invalid","to":"owner@example.invalid","cc":"","bcc":"","date":"2026-09-30T00:00:00Z","text":"Private fixture body","html":"","source_html":"","reply_to":"","message_id":"<message@example.invalid>","in_reply_to":"","references":"","attachments":[]}]}"#.utf8) }
        return Data(#"{"threads":[{"id":"thread","subject":"Planning","from":"sender@example.invalid","date":"2026-09-30T00:00:00Z","snippet":"Private fixture preview","unread":true,"starred":false}],"next_page":null}"#.utf8)
    }
}
