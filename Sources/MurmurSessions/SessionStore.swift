import Foundation
import Darwin

public enum SessionStoreError: LocalizedError {
    case invalidID, missingSession, alreadyExists, noteConflict, busy, recording
    public var errorDescription: String? {
        switch self {
        case .invalidID: "The meeting identifier is invalid."
        case .missingSession: "This meeting could not be found."
        case .alreadyExists: "A meeting with this identifier already exists."
        case .noteConflict: "These notes changed in another app. Your draft is still here; reload the saved version before replacing it."
        case .busy: "The notes folder could not be locked for saving."
        case .recording: "This meeting is still recording or saving. Try again when it has finished."
        }
    }
}

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
/// Machine without any help, and readable by a person when something has gone wrong.
/// Mutations use a cross-process file lock. Files are replaced atomically, and note edits
/// can require an expected version so an AI client cannot overwrite a newer manual edit.
public final class SessionStore: Sendable {
    public let root: URL

    public static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["MURMUR_SESSIONS_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public init(root: URL = SessionStore.defaultRoot) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - Paths

    public func directory(for id: String) -> URL {
        guard Self.isValidID(id) else { return root.appendingPathComponent(".invalid-session") }
        let candidate = root.appendingPathComponent(id, isDirectory: true)
        guard candidate.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL
                == root.resolvingSymlinksInPath().standardizedFileURL else {
            return root.appendingPathComponent(".invalid-session")
        }
        return candidate
    }

    public static func isValidID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$", options: .regularExpression) != nil
    }

    private func validate(_ id: String, mustExist: Bool = true) throws {
        guard Self.isValidID(id), directory(for: id).lastPathComponent == id else { throw SessionStoreError.invalidID }
        if mustExist, session(id: id) == nil { throw SessionStoreError.missingSession }
    }

    func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fd = open(root.appendingPathComponent(".store.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw SessionStoreError.busy }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw SessionStoreError.busy }
        defer { flock(fd, LOCK_UN) }
        return try operation()
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
        guard Self.isValidID(id), let data = try? Data(contentsOf: manifestURL(id)),
              let session = try? Self.decoder.decode(MeetingSession.self, from: data), session.id == id else { return nil }
        return session
    }

    public func create(_ session: MeetingSession) throws {
        try locked {
        try validate(session.id, mustExist: false)
        guard !FileManager.default.fileExists(atPath: directory(for: session.id).path) else { throw SessionStoreError.alreadyExists }
        try FileManager.default.createDirectory(at: directory(for: session.id), withIntermediateDirectories: true)
        try writeManifest(session)
        // An empty transcript file from the first moment, so a crash before the first
        // segment still leaves a recognisable, recoverable session on disk.
        let transcript = transcriptURL(session.id)
        if !FileManager.default.fileExists(atPath: transcript.path) {
            try Data().write(to: transcript, options: .atomic)
        }
        }
    }

    public func save(_ session: MeetingSession) throws {
        try locked {
            try validate(session.id)
            try writeManifest(session)
        }
    }

    private func writeManifest(_ session: MeetingSession) throws {
        let data = try Self.encoder.encode(session)
        try data.write(to: manifestURL(session.id), options: .atomic)
    }

    @discardableResult
    public func update(id: String, _ change: (inout MeetingSession) -> Void) throws -> MeetingSession {
        try locked {
            try validate(id)
            guard var session = session(id: id) else { throw SessionStoreError.missingSession }
            change(&session)
            guard session.id == id else { throw SessionStoreError.invalidID }
            try writeManifest(session)
            return session
        }
    }

    public func delete(id: String) throws {
        try locked {
            try validate(id)
            try FileManager.default.removeItem(at: directory(for: id))
        }
    }

    // MARK: - Transcript

    /// Appends segments as JSON lines. Called every flush while recording, so this must be
    /// cheap and must never rewrite what is already there.
    public func append(_ segments: [TranscriptSegment], to id: String) throws {
        guard !segments.isEmpty else { return }
        try locked {
        try validate(id)
        var payload = Data()
        for segment in segments {
            payload.append(try Self.lineEncoder.encode(segment))
            payload.append(0x0A)
        }
        let url = transcriptURL(id)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: payload)
        try handle.synchronize()
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
        try locked {
        try validate(id)
        var payload = Data()
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            payload.append(try Self.lineEncoder.encode(segment))
            payload.append(0x0A)
        }
        try payload.write(to: transcriptURL(id), options: .atomic)
        }
    }

    // MARK: - Notes

    /// Private editor recovery. Drafts are never included in MCP responses or exports.
    public func editingDraft(for id: String) -> EditingDraft? {
        guard let data = try? Data(contentsOf: directory(for: id).appendingPathComponent("editing-draft.json")) else { return nil }
        return try? Self.decoder.decode(EditingDraft.self, from: data)
    }

    public func saveEditingDraft(_ text: String, baseVersion: Int, for id: String) throws {
        try locked {
            try validate(id)
            let draft = EditingDraft(text: text, baseVersion: baseVersion)
            guard editingDraft(for: id) != draft else { return }
            try Self.encoder.encode(draft).write(to: directory(for: id).appendingPathComponent("editing-draft.json"), options: .atomic)
        }
    }

    public func clearEditingDraft(for id: String, matching text: String) throws {
        try locked {
            try validate(id)
            guard editingDraft(for: id)?.text == text else { return }
            try FileManager.default.removeItem(at: directory(for: id).appendingPathComponent("editing-draft.json"))
        }
    }

    public func bullets(for id: String) -> [NoteBullet] {
        guard let data = try? Data(contentsOf: bulletsURL(id)) else { return [] }
        return (try? Self.decoder.decode([NoteBullet].self, from: data)) ?? []
    }

    public func saveBullets(_ bullets: [NoteBullet], for id: String) throws {
        try locked {
        try validate(id)
        let data = try Self.encoder.encode(bullets)
        try data.write(to: bulletsURL(id), options: .atomic)
        }
    }

    public func note(for id: String) -> String? {
        try? String(contentsOf: noteURL(id), encoding: .utf8)
    }

    /// Saves a note, keeping the previous one as a numbered revision. Nothing that writes a
    /// note — you, the on-device model, or Claude — can destroy an earlier version.
    public func saveNote(_ text: String, for id: String, expectedVersion: Int? = nil,
                         source: String? = nil, template: SummaryTemplate? = nil) throws {
        try locked {
        try validate(id)
        guard var session = session(id: id) else { throw SessionStoreError.missingSession }
        guard !session.state.isInterrupted else { throw SessionStoreError.recording }
        if let expectedVersion, expectedVersion != noteVersion(for: id) { throw SessionStoreError.noteConflict }
        let url = noteURL(id)
        if let current = note(for: id), current == text { return }
        var revisionURL: URL?
        if FileManager.default.fileExists(atPath: url.path) {
            let dir = directory(for: id)
            var n = 1
            while FileManager.default.fileExists(atPath: dir.appendingPathComponent("note.\(n).md").path) { n += 1 }
            // Copy, then atomically replace: a failed write must leave the current note intact.
            let backup = dir.appendingPathComponent("note.\(n).md")
            try FileManager.default.copyItem(at: url, to: backup)
            revisionURL = backup
        }
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch {
            // The current note is intact. Remove the unused backup so a failed edit
            // does not invalidate another client's expected version.
            if let revisionURL { try? FileManager.default.removeItem(at: revisionURL) }
            throw error
        }
        session.state = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .raw : .noted
        session.noteSource = source
        session.summaryTemplate = template?.rawValue
        try writeManifest(session)
        }
    }

    public func noteRevisionCount(for id: String) -> Int {
        let dir = directory(for: id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.range(of: "^note\\.[0-9]+\\.md$", options: .regularExpression) != nil }.count
    }

    public func noteVersion(for id: String) -> Int {
        noteRevisionCount(for: id) + (note(for: id) == nil ? 0 : 1)
    }

    public func noteRevisions(for id: String) -> [NoteRevision] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory(for: id).path)) ?? []
        return names.compactMap { name in
            guard name.range(of: "^note\\.[0-9]+\\.md$", options: .regularExpression) != nil,
                  let number = Int(name.dropFirst(5).dropLast(3)),
                  let text = try? String(contentsOf: directory(for: id).appendingPathComponent(name), encoding: .utf8) else { return nil }
            return NoteRevision(number: number, text: text)
        }.sorted { $0.number > $1.number }
    }

    /// A new notepad is useful before a call or for thoughts that need no recording.
    public func createNote(title: String = "Untitled note") throws -> MeetingSession {
        let now = Date()
        let session = MeetingSession(id: MeetingSession.makeID(for: now), title: title, startedAt: now,
                                     endedAt: now, state: .raw, engine: "Notes")
        try create(session)
        return session
    }

    // MARK: - Recovery

    /// Any session still marked as recording or finalising was interrupted — a crash, a
    /// force-quit, a dead battery. Its flushed segments are kept and it becomes `raw`.
    @discardableResult
    public func recoverInterrupted() -> [MeetingSession] {
        var recovered: [MeetingSession] = []
        for var session in listSessions() where session.state.isInterrupted {
            let segments = transcript(for: session.id)
            session.state = note(for: session.id)?.isEmpty == false ? .noted : .raw
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
    public func search(_ query: String, limit: Int = 50, contextSeconds: TimeInterval = 20, since: Date? = nil) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, limit > 0 else { return [] }
        var hits: [SearchHit] = []
        for session in listSessions() {
            if let since, session.startedAt < since { continue }
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

    /// Search one result per meeting, including hand-written notes and summaries. The
    /// Library uses this off the main actor; MCP exposes the same result set.
    public func findSessions(_ query: String, since: Date? = nil, limit: Int = 200) -> [SessionMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, limit > 0 else { return [] }
        var matches: [SessionMatch] = []
        func contains(_ text: String) -> Bool { text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        func excerpt(_ text: String) -> String {
            guard let match = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { return String(text.prefix(180)) }
            let start = text.index(match.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(match.upperBound, offsetBy: 120, limitedBy: text.endIndex) ?? text.endIndex
            return (start > text.startIndex ? "…" : "") + text[start..<end].replacingOccurrences(of: "\n", with: " ") + (end < text.endIndex ? "…" : "")
        }
        for session in listSessions() {
            if let since, session.startedAt < since { continue }
            let metadata = ([session.title, session.app ?? ""] + session.speakers + session.attendees.map(\.name)).joined(separator: " · ")
            if contains(metadata) {
                matches.append(SessionMatch(session: session, snippet: excerpt(metadata), location: "Meeting", timestamp: nil))
            } else if let note = note(for: session.id), contains(note) {
                matches.append(SessionMatch(session: session, snippet: excerpt(note), location: "Notes", timestamp: nil))
            } else if let bullet = bullets(for: session.id).first(where: { contains($0.text) }) {
                matches.append(SessionMatch(session: session, snippet: excerpt(bullet.text), location: "Your notes", timestamp: bullet.at))
            } else if let segment = transcript(for: session.id).first(where: { contains($0.text) }) {
                matches.append(SessionMatch(session: session, snippet: excerpt(segment.text), location: "Transcript", timestamp: segment.start))
            }
            if matches.count >= limit { break }
        }
        return matches
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

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var lineEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
