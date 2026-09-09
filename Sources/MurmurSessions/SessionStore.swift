import Foundation

/// Plain files under Application Support, one directory per session.
///
/// ```
/// sessions/2026-09-09T14-32-11/
/// ├── session.json      manifest
/// ├── transcript.jsonl  one segment per line, append-only, flushed while recording
/// ├── notes.json        the bullets you typed, each with its timestamp
/// ├── note.md           the current note; earlier versions kept as note.1.md, note.2.md …
/// ```
///
/// Files rather than SQLite on purpose: they are greppable, diffable, backed up by Time
/// Machine without any help, and readable by a person when something has gone wrong. The
/// store holds no state of its own, so the same instance is safe to use from the app and
/// from the MCP process at once — writes are atomic per file, and the transcript is only
/// ever appended to.
public final class SessionStore: Sendable {
    public let root: URL

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public init(root: URL = SessionStore.defaultRoot) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - Paths

    public func directory(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    private func manifestURL(_ id: String) -> URL { directory(for: id).appendingPathComponent("session.json") }
    private func transcriptURL(_ id: String) -> URL { directory(for: id).appendingPathComponent("transcript.jsonl") }
    private func bulletsURL(_ id: String) -> URL { directory(for: id).appendingPathComponent("notes.json") }
    private func noteURL(_ id: String) -> URL { directory(for: id).appendingPathComponent("note.md") }

    // MARK: - Manifests

    public func listSessions() -> [MeetingSession] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        return names
            .compactMap { session(id: $0) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func session(id: String) -> MeetingSession? {
        guard let data = try? Data(contentsOf: manifestURL(id)) else { return nil }
        return try? Self.decoder.decode(MeetingSession.self, from: data)
    }

    public func create(_ session: MeetingSession) throws {
        try FileManager.default.createDirectory(at: directory(for: session.id), withIntermediateDirectories: true)
        try save(session)
        // An empty transcript file from the first moment, so a crash before the first
        // segment still leaves a recognisable, recoverable session on disk.
        let transcript = transcriptURL(session.id)
        if !FileManager.default.fileExists(atPath: transcript.path) {
            FileManager.default.createFile(atPath: transcript.path, contents: Data())
        }
    }

    public func save(_ session: MeetingSession) throws {
        let data = try Self.encoder.encode(session)
        try data.write(to: manifestURL(session.id), options: .atomic)
    }

    public func delete(id: String) throws {
        try FileManager.default.removeItem(at: directory(for: id))
    }

    // MARK: - Transcript

    /// Appends segments as JSON lines. Called every flush while recording, so this must be
    /// cheap and must never rewrite what is already there.
    public func append(_ segments: [TranscriptSegment], to id: String) throws {
        guard !segments.isEmpty else { return }
        var payload = Data()
        for segment in segments {
            payload.append(try Self.lineEncoder.encode(segment))
            payload.append(0x0A)
        }
        let url = transcriptURL(id)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            try payload.write(to: url, options: .atomic)
        }
    }

    public func transcript(for id: String) -> [TranscriptSegment] {
        guard let data = try? Data(contentsOf: transcriptURL(id)) else { return [] }
        return data
            .split(separator: 0x0A)
            .compactMap { try? Self.decoder.decode(TranscriptSegment.self, from: $0) }
            .sorted { $0.start < $1.start }
    }

    /// Rewrites the whole transcript. Used only after finalisation — for diarization labels
    /// and manual speaker renames — never while a recording is appending.
    public func replaceTranscript(_ segments: [TranscriptSegment], for id: String) throws {
        var payload = Data()
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            payload.append(try Self.lineEncoder.encode(segment))
            payload.append(0x0A)
        }
        try payload.write(to: transcriptURL(id), options: .atomic)
    }

    // MARK: - Notes

    public func bullets(for id: String) -> [NoteBullet] {
        guard let data = try? Data(contentsOf: bulletsURL(id)) else { return [] }
        return (try? Self.decoder.decode([NoteBullet].self, from: data)) ?? []
    }

    public func saveBullets(_ bullets: [NoteBullet], for id: String) throws {
        let data = try Self.encoder.encode(bullets)
        try data.write(to: bulletsURL(id), options: .atomic)
    }

    public func note(for id: String) -> String? {
        try? String(contentsOf: noteURL(id), encoding: .utf8)
    }

    /// Saves a note, keeping the previous one as a numbered revision. Nothing that writes a
    /// note — you, the on-device model, or Claude — can destroy an earlier version.
    public func saveNote(_ text: String, for id: String) throws {
        let url = noteURL(id)
        if FileManager.default.fileExists(atPath: url.path) {
            let dir = directory(for: id)
            var n = 1
            while FileManager.default.fileExists(atPath: dir.appendingPathComponent("note.\(n).md").path) { n += 1 }
            try FileManager.default.moveItem(at: url, to: dir.appendingPathComponent("note.\(n).md"))
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        if var session = session(id: id), session.state == .raw {
            session.state = .noted
            try save(session)
        }
    }

    public func noteRevisionCount(for id: String) -> Int {
        let dir = directory(for: id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix("note.") && $0.hasSuffix(".md") }.count
    }

    // MARK: - Recovery

    /// Any session still marked as recording or finalising was interrupted — a crash, a
    /// force-quit, a dead battery. Its flushed segments are kept and it becomes `raw`.
    @discardableResult
    public func recoverInterrupted() -> [MeetingSession] {
        var recovered: [MeetingSession] = []
        for var session in listSessions() where session.state.isInterrupted {
            let segments = transcript(for: session.id)
            session.state = .raw
            session.segmentCount = segments.count
            let lastEnd = segments.map(\.end).max() ?? 0
            session.duration = max(session.duration, lastEnd)
            if session.endedAt == nil {
                session.endedAt = session.startedAt.addingTimeInterval(session.duration)
            }
            try? save(session)
            recovered.append(session)
        }
        return recovered
    }

    // MARK: - Search

    /// Case-insensitive substring search across every transcript. Linear, which is fine
    /// until there are thousands of sessions; that is the point at which this becomes SQLite.
    public func search(_ query: String, limit: Int = 50, contextSeconds: TimeInterval = 20) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for session in listSessions() {
            let segments = transcript(for: session.id)
            for (index, segment) in segments.enumerated()
            where segment.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                let lower = segment.start - contextSeconds
                let upper = segment.end + contextSeconds
                var context: [TranscriptSegment] = []
                var i = index
                while i > 0, segments[i - 1].end >= lower { i -= 1 }
                while i < segments.count, segments[i].start <= upper {
                    context.append(segments[i])
                    i += 1
                }
                hits.append(SearchHit(
                    sessionID: session.id,
                    sessionTitle: session.title,
                    startedAt: session.startedAt,
                    segment: segment,
                    context: context
                ))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    // MARK: - Export

    /// The whole session as Markdown: the note if there is one, your bullets, then the
    /// transcript with timestamps and speakers. Paste-ready for Obsidian or a chat.
    public func markdown(for id: String, youLabel: String = "You") -> String {
        guard let session = session(id: id) else { return "" }
        var out = "# \(session.title)\n\n"
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .short
        out += "_\(df.string(from: session.startedAt)) · \(TimeFormat.clock(session.duration))"
        if let app = session.app { out += " · \(app)" }
        out += "_\n\n"

        if let note = note(for: id), !note.isEmpty {
            out += note.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        }

        let bullets = bullets(for: id)
        if !bullets.isEmpty {
            out += "## Your notes\n\n"
            for bullet in bullets {
                out += "- \(bullet.text)  `\(TimeFormat.clock(bullet.at))`\n"
            }
            out += "\n"
        }

        let segments = transcript(for: id)
        if !segments.isEmpty {
            out += "## Transcript\n\n"
            for segment in segments {
                let who = segment.speaker ?? (segment.source == .you ? youLabel : "Speaker")
                out += "**\(TimeFormat.clock(segment.start)) \(who):** \(segment.text)\n\n"
            }
        }
        return out
    }

    // MARK: - Coding

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
