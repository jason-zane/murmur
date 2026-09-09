import Foundation

/// Conference links are the only calendar URLs eligible for automatic opening.
/// A mention of a provider's domain in arbitrary text is not enough.
public enum MeetingLink {
    public static func conferenceURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let source = text.replacingOccurrences(of: "&amp;", with: "&")
        for match in detector.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let url = match.url, provider(for: url) != nil else { continue }
            return url
        }
        return nil
    }

    public static func provider(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        func domain(_ value: String) -> Bool { host == value || host.hasSuffix("." + value) }
        if host == "meet.google.com", path.range(of: "^/([a-z]{3}-[a-z]{4}-[a-z]{3}|lookup/[^/]+)$", options: .regularExpression) != nil { return "Google Meet" }
        if domain("zoom.us"), path.hasPrefix("/j/") || path.hasPrefix("/wc/join/") { return "Zoom" }
        if ["teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft"].contains(host),
           path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/") { return "Teams" }
        if domain("webex.com"), path.contains("/meet/") || path.contains("/join/") || path.contains("/j.php") { return "Webex" }
        if host == "whereby.com", path.count > 1 { return "Whereby" }
        if host == "meet.jit.si", path.count > 1 { return "Jitsi" }
        return nil
    }
}

public struct ScheduledMeeting: Sendable, Identifiable, Hashable {
    public let eventID: String
    public let start: Date
    public let end: Date
    public let url: URL
    /// Recurrences share an EventKit id; each occurrence must be handled independently.
    public var id: String { eventID + "@" + String(Int(start.timeIntervalSince1970)) }
    public init(eventID: String, start: Date, end: Date, url: URL) {
        self.eventID = eventID; self.start = start; self.end = end; self.url = url
    }
}

public enum MeetingOpeningPolicy {
    public static let leadTime: TimeInterval = 60

    /// Never replay an old meeting on launch or wake. Only an upcoming occurrence or a
    /// start missed by at most a small scheduling jitter is due.
    public static func due(_ meetings: [ScheduledMeeting], now: Date, enabledSince: Date,
                           handled: Set<String>) -> [ScheduledMeeting] {
        meetings.filter {
            !handled.contains($0.id) && $0.start >= enabledSince && $0.end > now
                && $0.start.timeIntervalSince(now) <= leadTime && $0.start.timeIntervalSince(now) >= -15
                && MeetingLink.provider(for: $0.url) != nil
        }.sorted { $0.start < $1.start }
    }
}

/// A call is absent only after both input and output stop. Muting a microphone must not
/// end a meeting that is still playing call audio. Manual recordings have no watched app.
public struct CallEndPolicy: Sendable {
    private var absentSince: Date?
    private var watchedID: String?
    public init() {}

    public mutating func shouldStop(bundleID: String?, hasInput: Bool, hasOutput: Bool,
                                    now: Date, delay: TimeInterval) -> Bool {
        if watchedID != bundleID { absentSince = nil; watchedID = bundleID }
        guard bundleID != nil else { absentSince = nil; return false }
        if hasInput || hasOutput { absentSince = nil; return false }
        if absentSince == nil { absentSince = now }
        return now.timeIntervalSince(absentSince ?? now) >= max(5, delay)
    }
}
