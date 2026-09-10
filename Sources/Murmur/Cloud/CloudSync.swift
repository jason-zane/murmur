import AppKit
import Foundation
import MurmurSessions
import Observation

struct CloudMeeting: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let starts_at: Date
    let ends_at: Date
    let meeting_url: URL?
    let attendees: [Attendee]
}

/// Keeps account ownership and HTTP outside the synchronization workflow so interrupted
/// requests and concurrent device edits can be exercised without a real user's account.
@MainActor
protocol CloudSyncTransport {
    var userID: String? { get }
    func request(_ path: String, method: String, body: Data?) async throws -> Data
}

@MainActor
private struct AccountSyncTransport: CloudSyncTransport {
    var userID: String? { CloudAccount.shared.credentials?.userID }

    func request(_ path: String, method: String, body: Data?) async throws -> Data {
        let account = CloudAccount.shared
        let base = account.siteURL.absoluteString.hasSuffix("/") ? account.siteURL : account.siteURL.appendingPathComponent("/")
        guard let url = URL(string: path, relativeTo: base) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("Bearer " + (try await account.accessToken()), forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try await CloudAccount.send(request)
    }
}

struct CloudSyncIssue: Identifiable {
    let id: String
    let title: String
    let message: String
}

/// What the account is doing, for the few places that show it. Signed out is `.off`, and
/// `.off` has no label on purpose: nothing about sync appears until there is an account.
enum SyncState: Equatable {
    case off
    case syncing
    case upToDate(Date?)
    case offline
    case attention(Int)
    case signInRequired

    var label: String? {
        switch self {
        case .off: nil
        case .syncing: "Syncing…"
        case .upToDate(let date):
            date.map { "Synced " + $0.formatted(.relative(presentation: .named)) } ?? "Up to date"
        case .offline: "Offline · syncs when you’re back"
        case .attention(let count): count == 1 ? "1 note didn’t sync" : "\(count) notes didn’t sync"
        case .signInRequired: "Sign in again to keep syncing"
        }
    }

    var symbol: String? {
        switch self {
        case .off, .upToDate: nil
        case .syncing: "arrow.triangle.2.circlepath"
        case .offline: "wifi.slash"
        case .attention: "exclamationmark.circle"
        case .signInRequired: "person.crop.circle.badge.exclamationmark"
        }
    }

    /// Something the user can act on, as opposed to something that resolves itself.
    var isProblem: Bool {
        switch self {
        case .attention, .signInRequired: true
        default: false
        }
    }
}

@MainActor @Observable
final class CloudSync {
    static let shared = CloudSync()
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var message: String?
    private(set) var needsAttention = false
    private(set) var requiresSignIn = false
    private(set) var conflictCount = 0
    private(set) var isOffline = false
    private(set) var issues: [CloudSyncIssue] = []
    private(set) var meetings: [CloudMeeting] = []
    private(set) var calendarConnected = false
    private(set) var calendarEmail: String?
    private(set) var calendarError: String?
    private var loop: Task<Void, Never>?
    private var generation = UUID()
    private let store: SessionStore
    private let transport: any CloudSyncTransport
    private let agendaChanged: @MainActor () -> Void
    private var index: SyncIndex?
    private let indexURL: URL
    private var observers: [any NSObjectProtocol] = []
    private var nudge: Task<Void, Never>?

    var state: SyncState {
        if transport.userID == nil { return .off }
        if isSyncing { return .syncing }
        if requiresSignIn { return .signInRequired }
        if !issues.isEmpty { return .attention(issues.count) }
        if isOffline { return .offline }
        return .upToDate(lastSyncedAt)
    }

    /// The last pass's problem with one note, if it had one.
    func issue(for id: String) -> CloudSyncIssue? {
        issues.first { $0.id == id }
    }

    init(store: SessionStore = SessionStore(), transport: (any CloudSyncTransport)? = nil,
         agendaChanged: @escaping @MainActor () -> Void = { MeetingSchedule.shared.refresh() }) {
        self.store = store
        self.transport = transport ?? AccountSyncTransport()
        self.agendaChanged = agendaChanged
        indexURL = store.root.deletingLastPathComponent().appendingPathComponent("cloud-sync.json")
        if let data = try? Data(contentsOf: indexURL) { index = try? JSONDecoder().decode(SyncIndex.self, from: data) }
    }

    /// The 30-second loop is the backstop. Coming back to the app and saving a note each
    /// run a pass sooner, which is what made a "Sync now" button unnecessary.
    func start() {
        guard loop == nil, !PreviewEnvironment.isActive else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in await CloudSync.shared.sync() }
            },
            // Downloads post this too; while a pass is running the change is ours.
            center.addObserver(forName: .murmurNotesChanged, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    let sync = CloudSync.shared
                    guard !sync.isSyncing else { return }
                    sync.scheduleNudge()
                }
            },
        ]
    }

    func stop() {
        generation = UUID()
        loop?.cancel()
        loop = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        nudge?.cancel()
        nudge = nil
        isOffline = false
        message = nil
        needsAttention = false
        requiresSignIn = false
        issues = []
        conflictCount = 0
        lastSyncedAt = nil
        meetings = []
        calendarConnected = false
        calendarEmail = nil
        calendarError = nil
        agendaChanged()
    }

    private func scheduleNudge() {
        nudge?.cancel()
        nudge = Task { [weak self] in
            do { try await Task.sleep(for: DS.Timing.syncDebounce) } catch { return }
            await self?.sync()
        }
    }

    func sync() async {
        guard !isSyncing, let userID = transport.userID, !PreviewEnvironment.isActive else { return }
        guard index == nil || index?.userID == userID else {
            needsAttention = true
            requiresSignIn = true
            message = "This Mac’s library is linked to a different Voice Notes account. Sign in to that account to continue syncing. Your notes stay on this Mac."
            return
        }
        let run = Run(userID: userID, generation: generation)
        isSyncing = true
        conflictCount = 0
        issues = []
        defer { isSyncing = false }
        do {
            if index == nil { index = SyncIndex(userID: userID, entries: [:]); try persistIndex() }
            loadAgenda(for: userID)
            var calendarWarning: String?
            // A rejected note must never prevent the calendar from refreshing.
            do {
                let agenda: CalendarPage = try await request("api/calendar", run: run)
                applyAgenda(agenda)
                saveAgenda(agenda, for: userID)
                calendarWarning = agenda.connection?.error
            } catch {
                try check(run)
                if Self.stopsPass(error) { throw error }
                calendarWarning = "Your calendar could not refresh. Cached meetings are still available."
            }

            var remote: [String: RemoteIndex] = [:], offset: Int? = 0
            while let pageOffset = offset {
                let page: IndexPage = try await request("api/sync?offset=\(pageOffset)", run: run)
                for row in page.sessions {
                    guard SessionStore.isValidID(row.id), row.version > 0 else { throw URLError(.cannotParseResponse) }
                    remote[row.id] = row
                }
                guard page.nextOffset == nil || page.nextOffset! > pageOffset else { throw URLError(.cannotParseResponse) }
                offset = page.nextOffset
            }
            let store = self.store
            let local = await Task.detached { store.listSessions() }.value
            try check(run)
            let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
            let ids = Set(localByID.keys).union(remote.keys).union(index?.entries.keys.map { $0 } ?? [])
            for id in ids.sorted() {
                try check(run)
                if localByID[id]?.state.isInterrupted == true { continue }
                do {
                    try await syncNote(id, cloud: remote[id], run: run)
                    try persistIndex()
                } catch {
                    try check(run)
                    if Self.stopsPass(error) { throw error }
                    issues.append(.init(id: id, title: localByID[id]?.title ?? "Note \(id)", message: error.localizedDescription))
                }
            }
            try persistIndex()
            requiresSignIn = false
            isOffline = false
            if issues.isEmpty { lastSyncedAt = Date() }
            needsAttention = !issues.isEmpty || calendarWarning != nil
            var messages: [String] = []
            if !issues.isEmpty {
                messages.append(issues.count == 1 ? "One note is waiting to sync. Other notes are up to date." : "\(issues.count) notes are waiting to sync. Other notes are up to date.")
            }
            if conflictCount > 0 { messages.append("Both versions were kept for \(conflictCount) changed notes. Look for “copy from this Mac” in your library.") }
            if let calendarWarning { messages.append(calendarWarning) }
            message = messages.isEmpty ? nil : messages.joined(separator: "\n")
        } catch {
            // A manual Sync now task may still finish after Sign out stopped the loop.
            // Discard its response and status instead of reviving the previous account.
            guard generation == run.generation, transport.userID == run.userID, !Task.isCancelled else { return }
            if error is CancellationError { return }
            needsAttention = true
            isOffline = Self.isOffline(error)
            if let error = error as? CloudHTTPError, error.status == 401 {
                requiresSignIn = true
                message = "Your account needs a new sign-in. Use Sign in again in Settings ▸ Account."
            } else if isOffline {
                message = "You’re offline. Keep working — your notes will sync when the connection returns."
            } else { message = error.localizedDescription }
        }
    }

    private func syncNote(_ id: String, cloud: RemoteIndex?, run: Run) async throws {
        let store = self.store
        let document = try await Task.detached { try store.cloudDocument(for: id) }.value
        try check(run)
        let previous = index?.entries[id]
        if cloud?.deleted_at != nil {
            // A cloud deletion never destroys this Mac's last copy.
            if let document { index?.entries[id] = .init(version: cloud!.version, fingerprint: document.fingerprint, removedLocally: true) }
            return
        }
        let action = CloudSyncAction.decide(localFingerprint: document?.fingerprint, previous: previous, remoteVersion: cloud?.version)
        switch action {
        case .unchanged: break
        case .keepLocalRemoval:
            if var entry = previous { entry.removedLocally = true; index?.entries[id] = entry }
        case .upload(let expectedVersion):
            guard let document else { return }
            do {
                let body = Upload(document: document, expectedVersion: expectedVersion)
                let result: RemoteDocument = try await request("api/sessions", method: "POST", body: CloudCoding.encoder.encode(body), run: run)
                try result.validate(id: id)
                // Remember the sent snapshot. An edit made during the request still
                // differs on the next pass, even if the response arrived after it.
                index?.entries[id] = .init(version: result.version, fingerprint: document.fingerprint)
            } catch let error as CloudHTTPError where error.status == 409 {
                // Another device may save between the index fetch and our upload.
                // Recover both copies now instead of blocking later notes for 30 seconds.
                try await download(id, document: document, preserveConflict: true, run: run)
            }
        case .download, .conflict:
            guard cloud != nil else { return }
            try await download(id, document: document, preserveConflict: action == .conflict, run: run)
        }
    }

    private func download(_ id: String, document: CloudDocument?, preserveConflict: Bool, run: Run) async throws {
        let result: RemoteDocument = try await request("api/sessions/" + id, run: run)
        try result.validate(id: id)
        if result.deleted_at != nil {
            if let document { index?.entries[id] = .init(version: result.version, fingerprint: document.fingerprint, removedLocally: true) }
            return
        }
        if result.document.fingerprint != document?.fingerprint {
            let store = self.store
            let fingerprint = document?.fingerprint
            let conflict = try await Task.detached {
                try store.importCloudDocument(result.document, expectedLocalFingerprint: fingerprint, preserveConflict: preserveConflict)
            }.value
            try check(run)
            if conflict != nil { conflictCount += 1 }
            NotificationCenter.default.post(name: .murmurNotesChanged, object: id)
        }
        index?.entries[id] = .init(version: result.version, fingerprint: result.document.fingerprint)
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, run: Run) async throws -> T {
        try check(run)
        let data = try await transport.request(path, method: method, body: body)
        try check(run)
        return try CloudCoding.decoder.decode(T.self, from: data)
    }

    private func check(_ run: Run) throws {
        try Task.checkCancellation()
        guard generation == run.generation, transport.userID == run.userID else { throw CancellationError() }
    }

    private static func stopsPass(_ error: any Error) -> Bool {
        error is CancellationError || (error as? CloudHTTPError)?.status == 401 || isOffline(error)
    }

    private static func isOffline(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(error.code)
    }

    private func persistIndex() throws {
        guard let index else { return }
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
    }

    private var agendaURL: URL { indexURL.deletingLastPathComponent().appendingPathComponent("cloud-agenda.json") }
    private func saveAgenda(_ value: CalendarPage, for userID: String) {
        try? CloudCoding.encoder.encode(CachedAgenda(userID: userID, page: value)).write(to: agendaURL, options: .atomic)
    }
    private func loadAgenda(for userID: String) {
        guard let data = try? Data(contentsOf: agendaURL),
              let value = try? CloudCoding.decoder.decode(CachedAgenda.self, from: data), value.userID == userID else { return }
        applyAgenda(value.page)
    }
    private func applyAgenda(_ agenda: CalendarPage) {
        meetings = agenda.events.filter { $0.ends_at > Date() }
        calendarConnected = agenda.connection != nil
        calendarEmail = agenda.connection?.email
        calendarError = agenda.connection?.error
        agendaChanged()
    }

    private struct Run { let userID: String; let generation: UUID }
    private struct SyncIndex: Codable { var userID: String; var entries: [String: CloudSyncEntry] }
    private struct RemoteIndex: Decodable { let id: String; let version: Int; let deleted_at: String? }
    private struct IndexPage: Decodable { let sessions: [RemoteIndex]; let nextOffset: Int? }
    private struct RemoteDocument: Decodable, Sendable {
        let id: String
        let version: Int
        let deleted_at: String?
        let document: CloudDocument
        func validate(id expected: String) throws {
            guard id == expected, document.session.id == expected, version > 0 else { throw URLError(.cannotParseResponse) }
        }
    }
    private struct Upload: Encodable { let document: CloudDocument; let expectedVersion: Int }
    private struct CachedAgenda: Codable { let userID: String; let page: CalendarPage }
    private struct CalendarPage: Codable {
        let events: [CloudMeeting]
        let connection: Connection?
        struct Connection: Codable { let email: String?; let updated_at: String?; let error: String? }
    }
}
