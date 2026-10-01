import Foundation
import Testing
@testable import Murmur

@MainActor @Suite(.serialized)
struct CalendarWorkspaceStoreTests {
    @Test func olderRangeResponseCannotReplaceNewerEventsOrWarnings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PausedCalendarTransport(), store = CalendarWorkspaceStore(transport: transport, root: root)
        let old = Task { await store.load(from: .distantPast, to: Date()) }
        while transport.responses.isEmpty { await Task.yield() }
        let latest = Task { await store.load(from: Date(), to: .distantFuture) }
        while transport.responses.count < 2 { await Task.yield() }
        transport.responses[1].resume(returning: Data(#"{"events":[],"calendars":[],"complete":false,"failures":[{"message":"Latest range unavailable"}]}"#.utf8))
        await latest.value
        transport.responses[0].resume(returning: Data(#"{"events":[],"calendars":[],"complete":true,"failures":[]}"#.utf8))
        await old.value
        #expect(store.needsAttention && store.message == "Latest range unavailable" && !store.complete && !store.loading)
    }
    @Test func duplicateProviderFailuresAreVisibleAndClearAfterRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = CalendarRangeTransport(), store = CalendarWorkspaceStore(transport: transport, root: root)
        transport.failures = true
        await store.load(from: .distantPast, to: .distantFuture)
        #expect(store.needsAttention)
        #expect(store.message == "Reconnect this account in Connected apps.")
        transport.failures = false
        transport.pending = true
        await store.load(from: .distantPast, to: .distantFuture)
        #expect(!store.needsAttention && store.updating)
        transport.pending = false
        await store.load(from: .distantPast, to: .distantFuture)
        #expect(!store.needsAttention && store.message == nil)
        transport.offline = true
        await store.load(from: .distantPast, to: .distantFuture)
        #expect(store.needsAttention && store.events.map(\.id) == ["past"])
        store.reset()
        #expect(!store.needsAttention && store.message == nil)
    }
    @Test func historyCacheIsIsolatedAndRestoresOffline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = CalendarRangeTransport()
        let start = Date(timeIntervalSince1970: 1_735_689_600), end = start.addingTimeInterval(86_400)
        let first = CalendarWorkspaceStore(transport: transport, root: root)
        await first.load(from: start, to: end)
        #expect(first.complete && first.events.map(\.id) == ["past"])
        #expect(transport.paths.first?.contains("api/calendar/events?from=") == true)
        transport.offline = true
        let restarted = CalendarWorkspaceStore(transport: transport, root: root)
        await restarted.load(from: start, to: end)
        #expect(restarted.events.map(\.id) == ["past"])
        #expect(!restarted.complete && restarted.message != nil)
        transport.userID = "another-account"
        await restarted.load(from: start, to: end)
        #expect(restarted.events.isEmpty && restarted.calendars.isEmpty)
    }
    @Test func completeEmptyCacheRemainsAuthoritativeOffline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = CalendarRangeTransport()
        transport.empty = true
        let store = CalendarWorkspaceStore(transport: transport, root: root)
        await store.load(from: .distantPast, to: .distantFuture)
        #expect(store.hasAuthoritativeSnapshot && store.events.isEmpty)
        transport.pending = true
        await store.load(from: .distantPast, to: .distantFuture)
        #expect(store.hasAuthoritativeSnapshot && !store.complete)
        transport.offline = true
        let restarted = CalendarWorkspaceStore(transport: transport, root: root)
        await restarted.load(from: .distantPast, to: .distantFuture)
        #expect(restarted.hasAuthoritativeSnapshot && restarted.events.isEmpty)
        // The view must pass this empty snapshot, rather than nil (legacy agenda fallback).
        let cloudEvents = restarted.hasAuthoritativeSnapshot || !restarted.events.isEmpty ? restarted.events : nil
        #expect(cloudEvents != nil && cloudEvents?.isEmpty == true)
        transport.userID = "another-account"
        await restarted.load(from: .distantPast, to: .distantFuture)
        #expect(!restarted.hasAuthoritativeSnapshot)
    }
    @Test func refreshKeepsVisibleEventsWhileRequestIsInFlight() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = CalendarRangeTransport(), store = CalendarWorkspaceStore(transport: transport, root: root)
        await store.load(from: .distantPast, to: .distantFuture)
        transport.onRequest = { #expect(store.events.map(\.id) == ["past"]) }
        await store.load(from: .distantPast, to: .distantFuture)
    }
    @Test func olderBackendKeepsDownloadedHistoryAndExplainsUpgrade() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = CalendarRangeTransport(), store = CalendarWorkspaceStore(transport: transport, root: root)
        await store.load(from: .distantPast, to: .distantFuture)
        transport.missingEndpoint = true
        await store.load(from: .distantPast, to: .distantFuture)
        #expect(store.events.map(\.id) == ["past"])
        #expect(!store.complete && store.message?.contains("hosted workspace upgrade") == true)
    }
    @Test func signOutDuringResponseClearsStateWithoutCachingTheResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = CalendarRangeTransport(), store = CalendarWorkspaceStore(transport: transport, root: root)
        await store.load(from: .distantPast, to: .distantFuture)
        transport.signOutDuringRequest = true
        await store.load(from: .distantPast, to: .distantFuture)
        #expect(store.events.isEmpty && !store.loading && !store.complete)
    }
}
@MainActor private final class PausedCalendarTransport: CloudSyncTransport {
    var userID: String? = "calendar-owner"
    var responses: [CheckedContinuation<Data, Never>] = []
    func request(_ path: String, method: String, body: Data?) async throws -> Data {
        await withCheckedContinuation { responses.append($0) }
    }
}
@MainActor private final class CalendarRangeTransport: CloudSyncTransport {
    var userID: String? = "calendar-owner"
    var offline = false
    var empty = false
    var pending = false
    var failures = false
    var onRequest: (() -> Void)?
    var missingEndpoint = false
    var signOutDuringRequest = false
    var paths: [String] = []
    func request(_ path: String, method: String, body: Data?) async throws -> Data {
        paths.append(path)
        onRequest?()
        if missingEndpoint { throw CloudHTTPError(status: 404, message: "Not found") }
        if offline { throw URLError(.notConnectedToInternet) }
        if signOutDuringRequest { userID = nil }
        if failures { return Data(#"{"events":[],"calendars":[],"complete":false,"failures":[{"message":"Reconnect this account in Connected apps."},{"message":"Reconnect this account in Connected apps."}]}"#.utf8) }
        if pending { return Data(#"{"events":[],"calendars":[],"complete":false,"pending":1,"failures":[]}"#.utf8) }
        if empty { return Data(#"{"events":[],"calendars":[],"complete":true,"failures":[]}"#.utf8) }
        return Data(#"{"events":[{"id":"past","title":"Historic meeting","starts_at":"2025-01-01T00:00:00Z","ends_at":"2025-01-01T01:00:00Z","attendees":[]}],"calendars":[],"complete":true,"failures":[]}"#.utf8)
    }
}
