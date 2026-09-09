import Foundation

/// Where a session is in its life. Persisted in the manifest, so an interrupted session can
/// be recognised and recovered on the next launch rather than silently lost.
public enum SessionState: String, Codable, Sendable {
    /// Audio is being captured and segments are being appended.
    case recording
    /// Capture has stopped; the transcript is being completed.
    case finalising
    /// Transcribed, no note written yet.
    case raw
    /// A note exists — written by hand, by the on-device model, or by Claude.
    case noted

    public var isInterrupted: Bool { self == .recording || self == .finalising }
}

/// Which capture stream a segment came from. The two are never mixed, which is what makes
/// "you versus everyone else" free: the mic is you, the process tap is the call.
public enum AudioStreamSource: String, Codable, Sendable {
    case you
    case call
}

/// One stretch of speech with a position in the meeting.
///
/// Times are seconds from the start of the session, not wall-clock, so a transcript can be
/// read back against the bullets you typed without timezone arithmetic.
public struct TranscriptSegment: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var source: AudioStreamSource
    /// Display name. `nil` until diarization or a manual label assigns one; the `you`
    /// stream is labelled at read time rather than stored, so a rename never rewrites files.
    public var speaker: String?
    public var text: String

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        source: AudioStreamSource,
        speaker: String? = nil,
        text: String
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.source = source
        self.speaker = speaker
        self.text = text
    }
}

/// A line you typed in the notepad, stamped with when in the meeting you typed it.
///
/// The timestamp is the whole point: it is what lets the note-fusion step find the part of
/// the transcript a bullet refers to without a model having to read the whole meeting.
public struct NoteBullet: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var at: TimeInterval
    public var text: String

    public init(id: UUID = UUID(), at: TimeInterval, text: String) {
        self.id = id
        self.at = at
        self.text = text
    }
}

public struct Attendee: Codable, Sendable, Hashable {
    public var name: String
    public var email: String?

    public init(name: String, email: String? = nil) {
        self.name = name
        self.email = email
    }
}

/// The manifest for one meeting: everything except the transcript and notes themselves,
/// which live in sibling files so they can be appended to and revised independently.
public struct MeetingSession: Codable, Sendable, Identifiable, Hashable {
    /// Directory name. ISO-8601 with colons replaced, so it sorts chronologically in Finder.
    public var id: String
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var state: SessionState

    /// Human label of the app the call ran in — "Zoom", "Google Meet" — if detection knew.
    public var app: String?
    public var bundleID: String?
    /// The calendar event this session was linked to, when there was one.
    public var calendarEventID: String?
    public var attendees: [Attendee]
    /// Every distinct speaker name that appears in the transcript, for the Library row.
    public var speakers: [String]
    /// Which transcription engine produced the transcript.
    public var engine: String
    public var segmentCount: Int
    /// Seconds. Kept in the manifest so the Library never has to open a transcript.
    public var duration: TimeInterval
    /// Optional additions keep manifests written by earlier Murmur versions readable.
    public var pinned: Bool?
    public var noteSource: String?
    public var summaryTemplate: String?

    public var isPinned: Bool { pinned == true }
    public var isNoteOnly: Bool { engine == "Notes" }

    public init(
        id: String,
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        state: SessionState = .recording,
        app: String? = nil,
        bundleID: String? = nil,
        calendarEventID: String? = nil,
        attendees: [Attendee] = [],
        speakers: [String] = [],
        engine: String,
        segmentCount: Int = 0,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.state = state
        self.app = app
        self.bundleID = bundleID
        self.calendarEventID = calendarEventID
        self.attendees = attendees
        self.speakers = speakers
        self.engine = engine
        self.segmentCount = segmentCount
        self.duration = duration
    }

    /// The suffix prevents two notes created in the same second from sharing a directory.
    public static func makeID(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: date) + "-" + UUID().uuidString.prefix(8).lowercased()
    }
}

/// One search result: the matching segment plus a little of what was said around it.
public struct SearchHit: Codable, Sendable, Identifiable, Hashable {
    public var id: String { "\(sessionID)/\(segment.id.uuidString)" }
    public var sessionID: String
    public var sessionTitle: String
    public var startedAt: Date
    public var segment: TranscriptSegment
    /// Segments within a few seconds either side, in order, including the match itself.
    public var context: [TranscriptSegment]

    public init(
        sessionID: String,
        sessionTitle: String,
        startedAt: Date,
        segment: TranscriptSegment,
        context: [TranscriptSegment]
    ) {
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.startedAt = startedAt
        self.segment = segment
        self.context = context
    }
}

public enum TimeFormat {
    /// `m:ss` under an hour, `h:mm:ss` above it — the readout used everywhere a duration
    /// or position is shown.
    public static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(min(max(0, seconds.rounded()), Double(Int.max / 2)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
