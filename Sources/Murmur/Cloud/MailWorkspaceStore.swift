import Foundation
import CryptoKit
import Observation
import MurmurSessions

struct MailAccount: Codable, Identifiable, Sendable {
    let id: String
    let email: String?
    var signature: String? = nil
    var label: String { email ?? "Gmail account" }
}
struct MailThread: Codable, Identifiable, Sendable {
    let id: String
    let subject: String
    let from: String
    let date: String
    let snippet: String
    let unread: Bool
    let starred: Bool
    var accountID: String? = nil
    var identity: String { (accountID ?? "") + "|" + id }
}
struct MailAttachment: Codable, Identifiable, Sendable {
    var id: String? = nil
    let name: String
    let type: String
    var size: Int? = nil
    var data: String? = nil
    var cid: String? = nil
}
struct MailMessage: Codable, Identifiable, Sendable {
    let id: String
    let thread_id: String
    let subject: String
    let from: String
    let to: String
    let cc: String
    let bcc: String
    let date: String
    let text: String
    let html: String
    let source_html: String
    let reply_to: String
    let message_id: String
    let in_reply_to: String
    let references: String
    let attachments: [MailAttachment]
}
struct MailProviderDraft: Codable, Identifiable, Sendable {
    let id: String
    let message: MailMessage
    var accountID: String? = nil
    var identity: String { (accountID ?? "") + "|" + id }
}
struct MailOutboxItem: Codable, Identifiable, Sendable {
    let id: String
    let connection_id: String
    let subject: String
    let status: String
    let due_at: String
    let error: String?
}
/// Split mailbox lists only outside quoted names and angle-addresses.
func mailAddresses(_ value: String) -> [String] {
    var result: [String] = [], buffer = "", quoted = false, escaped = false, depth = 0
    for character in value {
        if escaped { buffer.append(character); escaped = false; continue }
        if character == "\\", quoted { buffer.append(character); escaped = true; continue }
        if character == "\"" { quoted.toggle() }
        if !quoted { if character == "<" { depth += 1 }; if character == ">" { depth = max(0, depth - 1) } }
        if !quoted && depth == 0 && (character == "," || character == ";") {
            let address = buffer.trimmingCharacters(in: .whitespacesAndNewlines); if !address.isEmpty { result.append(address) }; buffer = ""
        } else { buffer.append(character) }
    }
    let address = buffer.trimmingCharacters(in: .whitespacesAndNewlines); if !address.isEmpty { result.append(address) }
    return result
}
struct MailDraft: Codable, Identifiable, Sendable {
    var id = UUID().uuidString
    var operationID = UUID().uuidString
    var accountID: String
    var userID: String
    var providerID: String? = nil
    var revision: String? = nil
    var threadID: String? = nil
    var to = ""
    var cc = ""
    var bcc = ""
    var subject = ""
    var text = ""
    var html: String? = nil
    var replyID: String? = nil
    var references: String? = nil
    var attachments: [MailAttachment] = []
    var queued = false
    var cancelRequested: Bool? = nil
    var sendAt: Date? = nil
    var error: String? = nil
    var updatedAt = Date()
}

/// The native mailbox stores only content opened or listed by its owner. It has no
/// relationship with the notes sync index or third-party MCP permissions.
@MainActor @Observable
final class MailWorkspaceStore {
    private(set) var accounts: [MailAccount] = []
    private(set) var threads: [MailThread] = []
    private(set) var messages: [MailMessage] = []
    private(set) var drafts: [MailDraft] = []
    private(set) var providerDrafts: [MailProviderDraft] = []
    private(set) var providerPages: [String: String] = [:]
    private(set) var outbox: [MailOutboxItem] = []
    private(set) var pages: [String: String] = [:]
    private(set) var loading = false
    private(set) var notice: String?
    private(set) var offline = false
    private var owner: String?
    private var generation = UUID()
    private var readerGeneration = UUID()
    private var submitting: Set<String> = []
    private let transport: any CloudSyncTransport
    private let root: URL
    private struct AccountsPage: Codable { let accounts: [MailAccount]; let outbox: [MailOutboxItem] }
    private struct ThreadsPage: Codable { let threads: [MailThread]; let next_page: String? }
    private struct ReaderPage: Codable { let messages: [MailMessage] }
    private struct SavedDraft: Codable { let id: String; let revision: String }
    init(transport: (any CloudSyncTransport)? = nil, root: URL = SessionStore().root.deletingLastPathComponent().appendingPathComponent("mail")) {
        self.transport = transport ?? AccountSyncTransport(); self.root = root
    }
    func reset() {
        generation = UUID(); readerGeneration = UUID(); owner = nil
        providerDrafts = []; providerPages = [:]; accounts = []; threads = []; messages = []; drafts = []; outbox = []; pages = [:]
        loading = false; notice = nil; offline = false
    }
    private func key(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func file(_ name: String, userID: String) -> URL { root.appendingPathComponent(key(userID)).appendingPathComponent(key(name) + ".json") }
    private func read<T: Decodable>(_ name: String, userID: String) -> T? {
        guard let data = try? Data(contentsOf: file(name, userID: userID)) else { return nil }
        return try? CloudCoding.decoder.decode(T.self, from: data)
    }
    private func write<T: Encodable>(_ value: T, name: String, userID: String) throws {
        let path = file(name, userID: userID)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try CloudCoding.encoder.encode(value).write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
    private func current(_ userID: String) -> Bool {
        guard transport.userID == userID else { reset(); return false }; return true
    }
    private func path(_ params: [String: String]) -> String {
        var parts = URLComponents(); parts.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return "api/mail?" + (parts.percentEncodedQuery ?? "")
    }
    func load(accountID: String, query: String, more: Bool = false, metadataOnly: Bool = false) async {
        let run = UUID(); generation = run
        guard !PreviewEnvironment.isActive, let userID = transport.userID else { reset(); return }
        if owner != userID { reset(); owner = userID; generation = run }
        loading = true; notice = nil
        defer { if generation == run { loading = false } }
        if let cached: AccountsPage = read("accounts", userID: userID) { accounts = cached.accounts; outbox = cached.outbox }
        drafts = read("drafts", userID: userID) ?? []
        let cacheKey = "threads:" + accountID + ":" + query
        if !more { threads = read(cacheKey, userID: userID) ?? read("threads:" + accountID + ":" + (query.components(separatedBy: " ").first ?? query), userID: userID) ?? []; pages = [:] }
        do {
            let data = try await transport.request("api/mail", method: "GET", body: nil)
            guard generation == run, current(userID), !Task.isCancelled else { return }
            let page = try CloudCoding.decoder.decode(AccountsPage.self, from: data)
            accounts = page.accounts; outbox = page.outbox; offline = false
            try write(page, name: "accounts", userID: userID)
            if metadataOnly { await flushQueued(userID: userID); return }
            var items: [MailThread] = [], next: [String: String] = [:], terminal: Set<String> = [], failures: [String] = []
            for account in accounts.filter({ accountID.isEmpty || $0.id == accountID }) {
                if more && pages[account.id] == nil { continue }
                do {
                    let params = ["account": account.id, "q": query].merging(more ? pages[account.id].map { ["page": $0] } ?? [:] : [:]) { _, last in last }
                    let data = try await transport.request(path(params), method: "GET", body: nil)
                    guard generation == run, current(userID), !Task.isCancelled else { return }
                    let page = try CloudCoding.decoder.decode(ThreadsPage.self, from: data)
                    items += page.threads.map { var thread = $0; thread.accountID = account.id; return thread }
                    next[account.id] = page.next_page
                    if page.next_page == nil { terminal.insert(account.id) }
                } catch { failures.append(account.label + ": " + error.localizedDescription) }
            }
            guard generation == run, current(userID), !Task.isCancelled else { return }
            if failures.isEmpty {
                var unique: [String: MailThread] = [:]
                for thread in (more ? threads : []) + items { unique[thread.identity] = thread }
                threads = unique.values.sorted { $0.date > $1.date }; pages = more ? pages.merging(next) { _, new in new } : next
                for id in terminal { pages.removeValue(forKey: id) }
                try write(threads, name: cacheKey, userID: userID)
            } else { notice = failures.joined(separator: " · ") }
            await flushQueued(userID: userID)
        } catch {
            guard generation == run, current(userID), !Task.isCancelled else { return }
            offline = true
            if let http = error as? CloudHTTPError, http.status == 404 {
                notice = "Gmail needs the hosted workspace upgrade. Your saved drafts remain on this Mac."
            } else {
                notice = "Offline or unable to update · showing downloaded mail. New mail and provider search need a connection."
            }
        }
    }
    func open(_ thread: MailThread) async {
        let run = UUID(); readerGeneration = run
        guard let userID = transport.userID, let accountID = thread.accountID else { return }
        let cacheKey = "reader:" + thread.identity
        messages = read(cacheKey, userID: userID) ?? []
        do {
            let data = try await transport.request(path(["account": accountID, "thread": thread.id]), method: "GET", body: nil)
            guard readerGeneration == run, current(userID), !Task.isCancelled else { return }
            let page = try CloudCoding.decoder.decode(ReaderPage.self, from: data)
            messages = page.messages; try write(messages, name: cacheKey, userID: userID)
        } catch { if readerGeneration == run && current(userID) { notice = messages.isEmpty ? "This conversation has not been downloaded. Reconnect to open it." : "Showing your downloaded conversation." } }
    }
    func action(_ action: String, thread: MailThread) async throws {
        guard let userID = transport.userID, let account = thread.accountID else { throw CloudHTTPError(status: 401, message: "Sign in to manage Gmail.") }
        _ = try await transport.request("api/mail", method: "POST", body: JSONSerialization.data(withJSONObject: ["action": action, "account": account, "id": thread.id]))
        guard current(userID) else { throw CancellationError() }
    }
    func outboxAction(_ action: String, id: String) async throws {
        _ = try await transport.request("api/mail", method: "POST", body: JSONSerialization.data(withJSONObject: ["action": action, "id": id]))
    }
    func attachment(_ attachment: MailAttachment, message: MailMessage, accountID: String) async throws -> Data {
        guard let userID = transport.userID, let id = attachment.id else { throw CloudHTTPError(status: 404, message: "This attachment is unavailable.") }
        let run = generation
        let name = "attachment:" + accountID + ":" + message.id + ":" + id, cache = file(name, userID: userID)
        if let inline = attachment.data, let decoded = Data(base64Encoded: inline) { return decoded }
        if let cached = try? Data(contentsOf: cache) { return cached }
        let data = try await transport.request(path(["account": accountID, "message": message.id, "attachment": id, "filename": attachment.name]), method: "GET", body: nil)
        guard generation == run, current(userID) else { throw CancellationError() }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: cache, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
        return data
    }
    func clearDownloaded() throws {
        guard let userID = transport.userID else { return }
        generation = UUID(); readerGeneration = UUID(); loading = false
        let directory = root.appendingPathComponent(key(userID))
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try write(drafts, name: "drafts", userID: userID)
        try write(AccountsPage(accounts: accounts, outbox: []), name: "accounts", userID: userID)
        providerDrafts = []; providerPages = [:]; threads = []; messages = []; pages = [:]; notice = "Downloaded mail cleared. Your drafts remain on this Mac."
    }
    func saveLocal(_ draft: MailDraft) throws {
        guard let userID = transport.userID else { throw CloudHTTPError(status: 401, message: "Sign in to save a mail draft.") }
        guard draft.userID == userID else { throw CancellationError() }
        if owner != userID { reset(); owner = userID; drafts = read("drafts", userID: userID) ?? [] }
        var value = draft; value.updatedAt = Date()
        drafts.removeAll { $0.id == value.id }; drafts.append(value)
        try write(drafts, name: "drafts", userID: userID)
    }
    func deleteLocal(_ id: String) throws {
        guard let userID = transport.userID else { return }; drafts.removeAll { $0.id == id }
        try write(drafts, name: "drafts", userID: userID)
    }
    private func payload(_ draft: MailDraft) -> [String: Any] {
        func addresses(_ value: String) -> [String] {
            mailAddresses(value).map { address in
                if let start = address.firstIndex(of: "<"), let end = address.lastIndex(of: ">"), start < end { return String(address[address.index(after: start)..<end]) }
                return address
            }
        }
        var value: [String: Any] = ["connection_id": draft.accountID, "to": addresses(draft.to), "cc": addresses(draft.cc), "bcc": addresses(draft.bcc), "subject": draft.subject, "text": draft.text,
            "attachments": draft.attachments.map { attachment -> [String: Any] in var a: [String: Any] = ["name": attachment.name, "type": attachment.type, "data": attachment.data ?? ""]; a["cid"] = attachment.cid; return a }]
        value["id"] = draft.providerID; value["revision"] = draft.revision; value["thread_id"] = draft.threadID
        value["in_reply_to"] = draft.replyID; value["references"] = draft.references; value["html"] = draft.html
        return value
    }
    func loadProviderDrafts(accountID: String, more: Bool = false) async {
        struct DraftsPage: Decodable { let drafts: [MailProviderDraft]; let next_page: String? }
        guard let userID = transport.userID, current(userID) else { return }
        let run = UUID(); generation = run
        let name = "provider-drafts:" + accountID
        if !more { providerDrafts = read(name, userID: userID) ?? []; providerPages = [:] }
        var items: [MailProviderDraft] = [], next: [String: String] = [:], terminal: Set<String> = []
        do {
            for account in accounts.filter({ accountID.isEmpty || $0.id == accountID }) {
                if more && providerPages[account.id] == nil { continue }
                var params = ["account": account.id, "drafts": "1"]
                if more { params["page"] = providerPages[account.id] }
                let data = try await transport.request(path(params), method: "GET", body: nil)
                guard generation == run, current(userID), !Task.isCancelled else { return }
                let page = try CloudCoding.decoder.decode(DraftsPage.self, from: data)
                items += page.drafts.map { var draft = $0; draft.accountID = account.id; return draft }
                next[account.id] = page.next_page
                if page.next_page == nil { terminal.insert(account.id) }
            }
            guard generation == run, current(userID), !Task.isCancelled else { return }
            var unique: [String: MailProviderDraft] = [:]
            for draft in (more ? providerDrafts : []) + items { unique[draft.identity] = draft }
            providerDrafts = unique.values.sorted { $0.message.date > $1.message.date }; providerPages = more ? providerPages.merging(next) { _, new in new } : next
            for id in terminal { providerPages.removeValue(forKey: id) }
            try write(providerDrafts, name: name, userID: userID)
        } catch { if generation == run, current(userID) { notice = "Gmail drafts could not update. Showing downloaded drafts." } }
    }
    func openProviderDraft(_ provider: MailProviderDraft) async throws -> MailDraft {
        struct DraftPage: Decodable { let id: String; let revision: String; let message: MailMessage; let attachments: [MailAttachment] }
        guard let userID = transport.userID, let accountID = provider.accountID else { throw CancellationError() }
        if let local = drafts.first(where: { $0.accountID == accountID && $0.providerID == provider.id && !$0.queued && $0.cancelRequested != true }) { return local }
        let run = readerGeneration
        let data = try await transport.request(path(["account": accountID, "draft": provider.id]), method: "GET", body: nil)
        guard readerGeneration == run, current(userID) else { throw CancellationError() }
        let page = try CloudCoding.decoder.decode(DraftPage.self, from: data), message = page.message
        var draft = MailDraft(accountID: accountID, userID: userID)
        draft.providerID = page.id; draft.revision = page.revision; draft.threadID = message.thread_id
        draft.to = message.to; draft.cc = message.cc; draft.bcc = message.bcc
        draft.subject = message.subject == "(No subject)" ? "" : message.subject
        draft.text = message.text; draft.html = message.source_html.isEmpty ? nil : message.source_html
        draft.replyID = message.in_reply_to.isEmpty ? nil : message.in_reply_to
        draft.references = message.references.isEmpty ? nil : message.references; draft.attachments = page.attachments
        try saveLocal(draft); return draft
    }
    func forward(_ message: MailMessage, accountID: String) async throws -> MailDraft {
        struct ForwardPage: Decodable { let message: MailMessage; let attachments: [MailAttachment] }
        guard let userID = transport.userID else { throw CancellationError() }
        let run = readerGeneration
        let data = try await transport.request(path(["account": accountID, "forward": message.id]), method: "GET", body: nil)
        guard readerGeneration == run, current(userID) else { throw CancellationError() }
        let page = try CloudCoding.decoder.decode(ForwardPage.self, from: data)
        let signature = accounts.first(where: { $0.id == accountID })?.signature ?? ""
        var draft = MailDraft(accountID: accountID, userID: userID)
        draft.subject = "Fwd: " + page.message.subject
        draft.text = "\n\n" + signature + "\n\n---------- Forwarded message ----------\nFrom: " + page.message.from + "\nSubject: " + page.message.subject + "\n\n" + page.message.text
        if !page.message.source_html.isEmpty {
            let escaped = signature.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
            draft.html = "<p>" + escaped + "</p><p>Forwarded message</p><blockquote>" + page.message.source_html + "</blockquote>"
        }
        draft.attachments = page.attachments
        try saveLocal(draft); return draft
    }
    func saveProvider(_ draft: MailDraft) async throws -> MailDraft {
        try saveLocal(draft)
        guard let userID = transport.userID else { throw CancellationError() }
        let data = try await transport.request("api/mail", method: "POST", body: JSONSerialization.data(withJSONObject: ["action": "draft", "message": payload(draft)]))
        guard current(userID) else { throw CancellationError() }
        let response = try CloudCoding.decoder.decode(SavedDraft.self, from: data)
        var saved = draft; saved.providerID = response.id; saved.revision = response.revision; saved.error = nil
        try saveLocal(saved); return saved
    }
    func queue(_ draft: MailDraft) async throws {
        var frozen = draft; frozen.queued = true; frozen.error = nil; try saveLocal(frozen)
        guard let userID = transport.userID else { throw CancellationError() }
        try await submit(frozen, userID: userID)
    }
    private func submit(_ draft: MailDraft, userID: String) async throws {
        guard drafts.first(where: { $0.id == draft.id })?.queued == true else { return }
        submitting.insert(draft.id)
        defer { submitting.remove(draft.id) }
        var body: [String: Any] = ["action": "send", "operation_id": draft.operationID, "message": payload(draft)]
        if let date = draft.sendAt { body["due_at"] = ISO8601DateFormatter().string(from: date) }
        do {
            _ = try await transport.request("api/mail", method: "POST", body: JSONSerialization.data(withJSONObject: body))
        } catch {
            if let response = error as? CloudHTTPError, [400, 409, 413].contains(response.status), current(userID) {
                var failed = drafts.first(where: { $0.id == draft.id }) ?? draft; failed.queued = false; failed.error = response.localizedDescription; try saveLocal(failed)
            }
            throw error
        }
        guard current(userID) else { throw CancellationError() }
        if let saved = drafts.first(where: { $0.id == draft.id }), saved.cancelRequested == true {
            try await completeCancellation(saved, userID: userID)
        } else { try deleteLocal(draft.id) }
    }
    func cancelLocalQueue(_ id: String) async throws {
        guard var draft = drafts.first(where: { $0.id == id }), let userID = transport.userID else { return }
        draft.queued = false; draft.cancelRequested = true; try saveLocal(draft)
        if submitting.contains(id) { return }
        try await completeCancellation(draft, userID: userID)
    }
    private func completeCancellation(_ draft: MailDraft, userID: String) async throws {
        struct OperationPage: Decodable { struct Operation: Decodable { let status: String }; let operation: Operation? }
        var status: String? = "cancelled"
        do {
            _ = try await transport.request("api/mail", method: "POST", body: JSONSerialization.data(withJSONObject: ["action": "cancel", "id": draft.operationID, "account": draft.accountID]))
        } catch {
            guard let response = error as? CloudHTTPError, response.status == 409 else { throw error }
            let data = try await transport.request(path(["operation": draft.operationID]), method: "GET", body: nil)
            status = try CloudCoding.decoder.decode(OperationPage.self, from: data).operation?.status
            guard status != nil else { throw error }
        }
        guard current(userID) else { throw CancellationError() }
        var saved = draft; saved.cancelRequested = nil; saved.queued = false
        saved.error = status == "cancelled" ? nil : "Delivery has already started. Check Sent and Outbox before sending again."
        // A fresh operation is required if the recovered draft is sent later.
        saved.operationID = UUID().uuidString
        try saveLocal(saved)
    }
    private func flushQueued(userID: String) async {
        for draft in drafts.filter({ $0.cancelRequested == true }) {
            guard current(userID), !Task.isCancelled else { return }
            do { try await completeCancellation(draft, userID: userID) }
            catch { if current(userID), var saved = drafts.first(where: { $0.id == draft.id }) { saved.error = "Undo pending · reconnect to confirm cancellation."; try? saveLocal(saved) } }
        }
        for draft in drafts.filter(\.queued) {
            guard current(userID), !Task.isCancelled else { return }
            do { try await submit(draft, userID: userID) }
            catch { if current(userID) { if var failed = drafts.first(where: { $0.id == draft.id }) { failed.error = error.localizedDescription; try? saveLocal(failed) } } }
        }
    }
}
