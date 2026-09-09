import Foundation
import MurmurSessions

extension MCPServer {
    func callTool(_ name: String, _ args: [String: Any]) throws -> [String: Any] {
        let schema = definitions.first { $0["name"] as? String == name }?["inputSchema"] as? [String: Any]
        let keys = Set((schema?["properties"] as? [String: Any] ?? [:]).keys)
        guard Set(args.keys).isSubset(of: keys) else { throw InputError("Unknown argument. See tools/list for the input schema.") }
        switch name {
        case "list_sessions":
            let limit = try integer(args, "limit", default: 50, range: 1...200)
            let offset = try integer(args, "offset", default: 0, range: 0...1_000_000)
            let days = try integer(args, "days", default: 30, range: 1...36_500)
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            let query = try optionalString(args, "query"), app = try optionalString(args, "app"), speaker = try optionalString(args, "speaker")
            let all = store.listSessions().filter { s in
                guard s.startedAt >= cutoff else { return false }
                if let app, !(s.app ?? "").localizedCaseInsensitiveContains(app) { return false }
                let people = s.speakers + s.attendees.map(\.name)
                if let speaker, !people.contains(where: { $0.localizedCaseInsensitiveContains(speaker) }) { return false }
                if let query, !([s.title, s.app ?? ""] + people).joined(separator: " ").localizedStandardContains(query) { return false }
                return true
            }
            let page = Array(all.dropFirst(offset).prefix(limit))
            return object(["sessions": page.map(manifest), "count": page.count, "total": all.count,
                           "next_offset": offset + page.count < all.count ? offset + page.count : NSNull()])
        case "get_session":
            let s = try meeting(args)
            var out = manifest(s)
            out["bullets"] = store.bullets(for: s.id).map { ["at": $0.at, "t": TimeFormat.clock($0.at), "text": $0.text] }
            out["note"] = store.note(for: s.id) ?? NSNull()
            out["note_version"] = store.noteVersion(for: s.id)
            out["note_revisions"] = store.noteRevisionCount(for: s.id)
            return object(out)
        case "get_transcript":
            let s = try meeting(args)
            let from = try number(args, "from", default: 0), to = try number(args, "to", default: .greatestFiniteMagnitude)
            guard from >= 0, to >= from else { throw InputError("Use a non-negative time range with to >= from.") }
            let speaker = try optionalString(args, "speaker")
            let limit = try integer(args, "limit", default: 200, range: 1...500)
            let offset = try integer(args, "offset", default: 0, range: 0...1_000_000)
            let all = store.transcript(for: s.id).filter { seg in
                guard seg.end >= from, seg.start <= to else { return false }
                return speaker.map { Self.speaker(seg).localizedCaseInsensitiveCompare($0) == .orderedSame } ?? true
            }
            let page = Array(all.dropFirst(offset).prefix(limit))
            return object(["id": s.id, "title": s.title, "segments": page.map(segment), "count": page.count, "total": all.count,
                           "next_offset": offset + page.count < all.count ? offset + page.count : NSNull()])
        case "search":
            let query = try string(args, "query"), limit = try integer(args, "limit", default: 30, range: 1...200)
            let since = args["days"] == nil ? nil : Date().addingTimeInterval(-Double(try integer(args, "days", default: 30, range: 1...36_500)) * 86_400)
            let matches = store.findSessions(query, since: since, limit: limit)
            return object(["meetings": matches.map { hit -> [String: Any] in
                ["id": hit.id, "title": hit.session.title, "started_at": Self.iso(hit.session.startedAt),
                 "snippet": hit.snippet, "location": hit.location, "timestamp": hit.timestamp as Any? ?? NSNull()]
            }, "count": matches.count])
        case "save_summary":
            guard allowWrites else { throw InputError("This connection is read-only.") }
            let s = try meeting(args), note = try string(args, "text", maximum: 200_000)
            guard args["expected_version"] != nil else { throw InputError("expected_version is required; read get_session first.") }
            let version = try integer(args, "expected_version", default: 0, range: 0...1_000_000)
            try store.saveNote(note, for: s.id, expectedVersion: version, source: "Connected app", template: try template(args))
            return object(["id": s.id, "saved": true, "note_version": store.noteVersion(for: s.id)])
        default: throw InputError("Unknown tool.")
        }
    }

    var definitions: [[String: Any]] {
        func str(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
        func int(_ description: String, _ min: Int, _ max: Int) -> [String: Any] { ["type": "integer", "description": description, "minimum": min, "maximum": max] }
        func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = [], writes: Bool = false) -> [String: Any] {
            ["name": name, "description": description,
             "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
             "annotations": ["readOnlyHint": !writes, "destructiveHint": false, "idempotentHint": !writes, "openWorldHint": false]]
        }
        var tools = [
            tool("list_sessions", "List local meetings and notes, newest first. Use next_offset for more results.", [
                "days": int("Days back; default 30.", 1, 36_500), "query": str("Title, app or person substring."),
                "app": str("App name."), "speaker": str("Speaker or attendee name."),
                "limit": int("Page size; default 50.", 1, 200), "offset": int("Page offset; default 0.", 0, 1_000_000)]),
            tool("get_session", "Read metadata, user notes, saved summary and note_version.", ["id": str("Session id.")], required: ["id"]),
            tool("get_transcript", "Read timestamped speaker segments. Continue with next_offset until null to read the whole meeting.", [
                "id": str("Session id."), "from": ["type": "number", "minimum": 0], "to": ["type": "number", "minimum": 0],
                "speaker": str("Exact speaker name."), "limit": int("Page size; default 200.", 1, 500),
                "offset": int("Page offset; default 0.", 0, 1_000_000)], required: ["id"]),
            tool("search", "Search titles, people, summaries, personal notes and transcripts. One matching excerpt per meeting.", [
                "query": str("Text to find."), "days": int("Optional days back; default all.", 1, 36_500),
                "limit": int("Maximum meetings; default 30.", 1, 200)], required: ["query"]),
        ]
        if allowWrites {
            tools.append(tool("save_summary", "Save a Markdown summary as a new note revision. Requires user intent to save and the note_version from get_session; stale versions are rejected.", [
                "id": str("Session id."), "text": str("Markdown notes, at most 200,000 characters."),
                "expected_version": int("Current note_version from get_session.", 0, 1_000_000),
                "template": str("meeting, oneOnOne, standup, or interview.")], required: ["id", "text", "expected_version"], writes: true))
        }
        return tools
    }
}
