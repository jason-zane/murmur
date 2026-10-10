import AppKit
import Foundation
import Observation
import MurmurSessions

/// Calendar ranges have their own cache and request lifecycle. Browsing history never
/// changes the note sync index or the window used by meeting detection.
@MainActor @Observable
final class CalendarWorkspaceStore {
    private(set) var events: [CloudMeeting] = []
    private(set) var calendars: [Source] = []
    private(set) var loading = false
    private(set) var message: String?
    private(set) var needsAttention = false
    private(set) var complete = false
    private(set) var hasAuthoritativeSnapshot = false
    private(set) var updating = false
    private var generation = UUID()
    private var loadedRange: String?
    private let transport: any CloudSyncTransport
    private let root: URL
    struct Source: Codable, Identifiable, Sendable {
        let connection_id: String
        let calendar_id: String
        let name: String
        let selected: Bool
        var can_write: Bool? = nil
        var id: String { connection_id + "|" + calendar_id }
    }
    private struct Page: Codable {
        let events: [CloudMeeting]
        let calendars: [Source]
        let complete: Bool
        var pending: Int? = nil
        let failures: [Failure]
        struct Failure: Codable { let message: String }
    }
    private struct Cache: Codable { let userID: String; let page: Page; var authoritative: Bool? = nil }
    func saveEvent(event: CloudMeeting?, source: Source, title: String, start: Date, end: Date, allDay: Bool, location: String, description: String, guests: String, repeatFrequency: String, timeZone: String = TimeZone.current.identifier, reminder: String = "keep") async throws {
        let formatter = ISO8601DateFormatter()
        let dateOnly = DateFormatter(); dateOnly.calendar = Calendar(identifier: .gregorian)
        dateOnly.locale = Locale(identifier: "en_US_POSIX"); dateOnly.dateFormat = "yyyy-MM-dd"
        var body: [String: Any] = ["connection_id": source.connection_id, "calendar_id": source.calendar_id,
            "title": title, "start": allDay ? dateOnly.string(from: start) : formatter.string(from: start),
            "end": allDay ? dateOnly.string(from: end) : formatter.string(from: end), "all_day": allDay,
            "time_zone": timeZone, "location": location, "description": description,
            "attendees": guests.components(separatedBy: CharacterSet(charactersIn: ",;")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }]
        if reminder == "default" { body["reminders"] = ["useDefault": true] }
        else if reminder == "none" { body["reminders"] = ["useDefault": false, "overrides": []] }
        else if let minutes = Int(reminder) { body["reminders"] = ["useDefault": false, "overrides": [["method": "popup", "minutes": minutes]]] }
        if let event { body["id"] = event.id; body["etag"] = event.details?.etag }
        else if ["Daily", "Weekly", "Monthly"].contains(repeatFrequency) { body["recurrence"] = ["RRULE:FREQ=" + repeatFrequency.uppercased()] }
        _ = try await transport.request("api/calendar/events", method: "POST", body: JSONSerialization.data(withJSONObject: body))
    }
    func removeEvent(_ event: CloudMeeting) async throws {
        guard let connection = event.connection_id, let calendar = event.calendar_id, let etag = event.details?.etag else {
            throw CloudHTTPError(status: 409, message: "Reload this event before removing it.")
        }
        _ = try await transport.request("api/calendar/events", method: "DELETE", body: JSONSerialization.data(withJSONObject: ["connection_id": connection, "calendar_id": calendar, "id": event.id, "etag": etag]))
    }
    func reset() {
        generation = UUID(); loadedRange = nil
        events = []; calendars = []; message = nil; needsAttention = false; complete = false; hasAuthoritativeSnapshot = false; updating = false; loading = false
    }
    init(transport: (any CloudSyncTransport)? = nil, root: URL = SessionStore().root.deletingLastPathComponent().appendingPathComponent("calendar-ranges")) {
        self.transport = transport ?? AccountSyncTransport()
        self.root = root
    }
    func load(from start: Date, to end: Date, force: Bool = false) async {
        let run = UUID(); generation = run
        if PreviewEnvironment.isActive {
            reset(); message = PreviewEnvironment.calendarMessage; needsAttention = message != nil; return
        }
        guard let userID = transport.userID else {
            reset(); return
        }
        let userRoot = root.appendingPathComponent(Data(userID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_"))
        let file = userRoot.appendingPathComponent("\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970)).json")
        let range = userID + "|" + file.lastPathComponent
        let changedRange = loadedRange != range
        loadedRange = range
        complete = false; loading = true
        if changedRange { events = []; calendars = []; message = nil; needsAttention = false; hasAuthoritativeSnapshot = false }
        if changedRange, let data = try? Data(contentsOf: file), let cache = try? CloudCoding.decoder.decode(Cache.self, from: data), cache.userID == userID {
            events = cache.page.events; calendars = cache.page.calendars; hasAuthoritativeSnapshot = cache.authoritative ?? cache.page.complete
        }
        do {
            let formatter = ISO8601DateFormatter()
            var parts = URLComponents()
            parts.queryItems = [URLQueryItem(name: "from", value: formatter.string(from: start)), URLQueryItem(name: "to", value: formatter.string(from: end))]
            if force { parts.queryItems?.append(URLQueryItem(name: "refresh", value: "1")) }
            let data = try await transport.request("api/calendar/events?" + (parts.percentEncodedQuery ?? ""), method: "GET", body: nil)
            guard generation == run else { return }
            guard transport.userID == userID else { reset(); return }
            guard !Task.isCancelled else { loading = false; return }
            let page = try CloudCoding.decoder.decode(Page.self, from: data)
            events = page.events; calendars = page.calendars; complete = page.complete; hasAuthoritativeSnapshot = hasAuthoritativeSnapshot || page.complete; updating = (page.pending ?? 0) > 0
            needsAttention = !page.failures.isEmpty
            var seen: Set<String> = []
            let failures = page.failures.map(\.message).filter { seen.insert($0).inserted }
            message = failures.isEmpty ? ((page.pending ?? 0) > 0 ? "Updating calendars · showing downloaded events." : nil) : failures.joined(separator: " · ")
            try FileManager.default.createDirectory(at: userRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try CloudCoding.encoder.encode(Cache(userID: userID, page: page, authoritative: hasAuthoritativeSnapshot)).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            guard generation == run else { return }
            guard transport.userID == userID else { reset(); return }
            guard !Task.isCancelled else { loading = false; return }
            updating = false
            needsAttention = true
            if let http = error as? CloudHTTPError, http.status == 404 {
                message = "Google Calendar history needs the hosted workspace upgrade. Calendars on this Mac remain available."
            } else {
                message = events.isEmpty ? "Calendar could not load this period. Check Connected apps and try again." : "Offline or unable to update · showing downloaded events."
            }
        }
        if generation == run { loading = false }
    }
}
