import Foundation
import MurmurSessions
import Testing
@testable import Murmur

@MainActor @Suite(.serialized)
struct MailboxIdentityTests {
    @Test func stableDefaultsMatchWebAndUnknownFieldsRemainReadable() throws {
        #expect(MailboxColour.defaultColour("account") == .slate)
        #expect(MailboxColour.defaultColour("sample-work") == .amber)
        #expect(MailboxColour.defaultColour("é") == .slate)
        let old = try CloudCoding.decoder.decode(MailAccount.self, from: Data(#"{"id":"account","email":"owner@example.invalid"}"#.utf8))
        #expect(old.colour == .slate && old.icon == .initials)
        let future = try CloudCoding.decoder.decode(MailAccount.self, from: Data(#"{"id":"account","email":"owner@example.invalid","identity_colour":"unknown","identity_icon":"unknown"}"#.utf8))
        #expect(future.colour == .slate && future.icon == .initials)
    }
    @Test func identitySavePreservesSignatureAndCachesConfirmedAppearance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = IdentityFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox", metadataOnly: true)
        try await store.saveIdentity(accountID: "account", colour: .teal, icon: .work)
        #expect(store.accounts.first?.colour == .teal && store.accounts.first?.icon == .work)
        #expect(store.accounts.first?.signature == "Regards")
        #expect(transport.lastBody?["signature"] == nil && transport.posts == 1)
        transport.offline = true
        let restarted = MailWorkspaceStore(transport: transport, root: root)
        await restarted.load(accountID: "", query: "in:inbox", metadataOnly: true)
        #expect(restarted.offline && restarted.accounts.first?.colour == .teal)
        #expect(restarted.accounts.first?.icon == .work)
    }
    @Test func repeatedAndCancelledSaveCannotOverwriteLocalAppearance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = IdentityFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox", metadataOnly: true)
        transport.suspend = true
        let save = Task { try await store.saveIdentity(accountID: "account", colour: .violet, icon: .none) }
        while transport.pending == nil { await Task.yield() }
        await #expect(throws: CloudHTTPError.self) { try await store.saveIdentity(accountID: "account", colour: .teal, icon: .work) }
        #expect(transport.posts == 1)
        save.cancel(); transport.pending?.resume(returning: Data(#"{"saved":true}"#.utf8)); transport.pending = nil
        await #expect(throws: CancellationError.self) { try await save.value }
        #expect(store.accounts.first?.identity_colour == nil)
    }
    @Test func ownerChangeDuringSaveClearsPrivateState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = IdentityFixtureTransport(), store = MailWorkspaceStore(transport: transport, root: root)
        await store.load(accountID: "", query: "in:inbox", metadataOnly: true)
        transport.suspend = true
        let save = Task { try await store.saveIdentity(accountID: "account", colour: .teal, icon: .work) }
        while transport.pending == nil { await Task.yield() }
        transport.userID = "different-owner"; transport.pending?.resume(returning: Data(#"{"saved":true}"#.utf8)); transport.pending = nil
        await #expect(throws: CancellationError.self) { try await save.value }
        #expect(store.accounts.isEmpty)
    }
}
@MainActor private final class IdentityFixtureTransport: CloudSyncTransport {
    var userID: String? = "identity-owner"
    var offline = false
    var suspend = false
    var pending: CheckedContinuation<Data, Error>?
    var posts = 0
    var lastBody: [String: Any]?
    func request(_ path: String, method: String, body: Data?) async throws -> Data {
        if offline { throw URLError(.notConnectedToInternet) }
        if method == "POST" {
            posts += 1; lastBody = try body.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
            if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
            return Data(#"{"saved":true}"#.utf8)
        }
        return Data(#"{"accounts":[{"id":"account","email":"owner@example.invalid","signature":"Regards"}],"outbox":[]}"#.utf8)
    }
}
