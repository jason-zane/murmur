import Foundation
import MurmurSessions

// murmur-mcp — a local Model Context Protocol server over stdio.
//
// Claude Desktop spawns this process and talks JSON-RPC 2.0 to it, one message per line on
// stdin and stdout. It reads the same session directory the app writes and nothing else.
// It has no network access, listens on no port, and exits when its stdin closes. Logging
// goes to stderr only — stdout is the protocol.
//
// Tools are read-only on purpose. A write tool is obvious and useful, and it would also let
// a model overwrite a note you wrote by hand. It arrives once the read path has earned
// trust, and it will write a new revision rather than replace.

let store = SessionStore()
let serverName = "murmur"
let serverVersion = "0.2.0"
let protocolVersion = "2025-06-18"

func log(_ message: String) {
    FileHandle.standardError.write(Data(("murmur-mcp: " + message + "\n").utf8))
}

func send(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

func reply(_ id: Any, result: Any) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func fail(_ id: Any, code: Int, _ message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func text(_ string: String, isError: Bool = false) -> [String: Any] {
    var result: [String: Any] = ["content": [["type": "text", "text": string]]]
    if isError { result["isError"] = true }
    return result
}

let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func json(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else { return "{}" }
    return string
}

// MARK: - Shapes

@MainActor func manifest(_ s: MeetingSession) -> [String: Any] {
    var out: [String: Any] = [
        "id": s.id,
        "title": s.title,
        "started_at": iso.string(from: s.startedAt),
        "duration_seconds": Int(s.duration),
        "duration": TimeFormat.clock(s.duration),
        "state": s.state.rawValue,
        "speakers": s.speakers,
        "engine": s.engine,
        "segment_count": s.segmentCount,
    ]
    if let ended = s.endedAt { out["ended_at"] = iso.string(from: ended) }
    if let app = s.app { out["app"] = app }
    if !s.attendees.isEmpty { out["attendees"] = s.attendees.map(\.name) }
    return out
}

@MainActor func segmentShape(_ seg: TranscriptSegment) -> [String: Any] {
    [
        "t": TimeFormat.clock(seg.start),
        "start": seg.start,
        "end": seg.end,
        "speaker": seg.speaker ?? (seg.source == .you ? "You" : "Speaker"),
        "source": seg.source.rawValue,
        "text": seg.text,
    ]
}

// MARK: - Tools

let toolDefinitions: [[String: Any]] = [
    [
        "name": "list_sessions",
        "description": "List recorded meetings, newest first. Cheap: reads manifests only, never transcripts. Filter by how many days back, a title/speaker/app substring, a specific app, or a speaker name.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "days": ["type": "integer", "description": "Only sessions that started within this many days. Default 30."],
                "query": ["type": "string", "description": "Case-insensitive match against title, app and speaker names."],
                "app": ["type": "string", "description": "Only sessions from this app, e.g. Zoom."],
                "speaker": ["type": "string", "description": "Only sessions where this person spoke."],
                "limit": ["type": "integer", "description": "Maximum sessions to return. Default 50."],
            ],
        ],
    ],
    [
        "name": "get_session",
        "description": "One meeting's manifest, the bullets the user typed during it (each with its timestamp), and the current note if one exists. Enough to write or improve a note without reading the transcript.",
        "inputSchema": [
            "type": "object",
            "properties": ["id": ["type": "string", "description": "Session id from list_sessions."]],
            "required": ["id"],
        ],
    ],
    [
        "name": "get_transcript",
        "description": "The transcript of one meeting as timestamped, speaker-labelled segments. Optionally limit to a time range in seconds, or to one speaker, so 'the last ten minutes' is a small call.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "from": ["type": "number", "description": "Start of range, seconds from the beginning of the meeting."],
                "to": ["type": "number", "description": "End of range, seconds."],
                "speaker": ["type": "string", "description": "Only segments by this speaker."],
            ],
            "required": ["id"],
        ],
    ],
    [
        "name": "search",
        "description": "Full-text search across every meeting transcript. Returns matching segments with about twenty seconds of surrounding conversation and the session each came from.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "query": ["type": "string"],
                "days": ["type": "integer", "description": "Only meetings within this many days. Default: all."],
                "limit": ["type": "integer", "description": "Default 30."],
            ],
            "required": ["query"],
        ],
    ],
]

@MainActor func callTool(_ name: String, _ args: [String: Any]) -> [String: Any] {
    switch name {
    case "list_sessions":
        let days = args["days"] as? Int ?? 30
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let query = (args["query"] as? String)?.lowercased()
        let app = (args["app"] as? String)?.lowercased()
        let speaker = (args["speaker"] as? String)?.lowercased()
        let limit = args["limit"] as? Int ?? 50
        let sessions = store.listSessions().filter { s in
            guard s.startedAt >= cutoff else { return false }
            if let app, (s.app ?? "").lowercased() != app { return false }
            if let speaker, !s.speakers.contains(where: { $0.lowercased() == speaker }),
               !s.attendees.contains(where: { $0.name.lowercased() == speaker }) { return false }
            if let query {
                let hay = ([s.title, s.app ?? ""] + s.speakers + s.attendees.map(\.name)).joined(separator: " ").lowercased()
                if !hay.contains(query) { return false }
            }
            return true
        }.prefix(limit)
        return text(json(["sessions": sessions.map(manifest), "count": sessions.count]))

    case "get_session":
        guard let id = args["id"] as? String, let s = store.session(id: id) else {
            return text("No session with that id.", isError: true)
        }
        var out = manifest(s)
        out["bullets"] = store.bullets(for: id).map { ["t": TimeFormat.clock($0.at), "at": $0.at, "text": $0.text] }
        out["note"] = store.note(for: id) ?? NSNull()
        out["note_revisions"] = store.noteRevisionCount(for: id)
        return text(json(out))

    case "get_transcript":
        guard let id = args["id"] as? String, let s = store.session(id: id) else {
            return text("No session with that id.", isError: true)
        }
        let from = args["from"] as? Double ?? 0
        let to = args["to"] as? Double ?? .greatestFiniteMagnitude
        let speaker = (args["speaker"] as? String)?.lowercased()
        let segments = store.transcript(for: id).filter { seg in
            guard seg.end >= from, seg.start <= to else { return false }
            if let speaker {
                let name = (seg.speaker ?? (seg.source == .you ? "You" : "Speaker")).lowercased()
                return name == speaker
            }
            return true
        }
        return text(json([
            "id": s.id,
            "title": s.title,
            "segments": segments.map(segmentShape),
            "count": segments.count,
        ]))

    case "search":
        guard let query = args["query"] as? String, !query.isEmpty else {
            return text("A query is required.", isError: true)
        }
        let limit = args["limit"] as? Int ?? 30
        var hits = store.search(query, limit: limit * 4)
        if let days = args["days"] as? Int {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            hits = hits.filter { $0.startedAt >= cutoff }
        }
        let shaped = hits.prefix(limit).map { hit -> [String: Any] in
            [
                "session_id": hit.sessionID,
                "session_title": hit.sessionTitle,
                "started_at": iso.string(from: hit.startedAt),
                "match": segmentShape(hit.segment),
                "context": hit.context.map(segmentShape),
            ]
        }
        return text(json(["hits": shaped, "count": shaped.count]))

    default:
        return text("Unknown tool: \(name)", isError: true)
    }
}

// MARK: - Resources

let resourcePrefix = "murmur://sessions/"

@MainActor func listResources() -> [[String: Any]] {
    store.listSessions().prefix(100).map { s in
        [
            "uri": resourcePrefix + s.id,
            "name": s.title,
            "description": "\(iso.string(from: s.startedAt)) · \(TimeFormat.clock(s.duration))" + (s.app.map { " · \($0)" } ?? ""),
            "mimeType": "text/markdown",
        ]
    }
}

@MainActor func readResource(_ uri: String) -> [String: Any]? {
    guard uri.hasPrefix(resourcePrefix) else { return nil }
    let id = String(uri.dropFirst(resourcePrefix.count))
    guard store.session(id: id) != nil else { return nil }
    return ["contents": [["uri": uri, "mimeType": "text/markdown", "text": store.markdown(for: id)]]]
}

// MARK: - Loop

@MainActor func handle(_ message: [String: Any]) {
    let method = message["method"] as? String ?? ""
    let params = message["params"] as? [String: Any] ?? [:]
    guard let id = message["id"] else {
        // A notification. Nothing we need to act on.
        return
    }

    switch method {
    case "initialize":
        reply(id, result: [
            "protocolVersion": protocolVersion,
            "capabilities": ["tools": [:], "resources": [:]],
            "serverInfo": ["name": serverName, "version": serverVersion],
            "instructions": "Read-only access to the user's locally recorded meetings. Start with list_sessions; use get_session for the user's own bullets and any existing note; use get_transcript only when you need what was actually said. Everything here was captured on the user's Mac and never left it.",
        ])
    case "ping":
        reply(id, result: [:])
    case "tools/list":
        reply(id, result: ["tools": toolDefinitions])
    case "tools/call":
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        reply(id, result: callTool(name, args))
    case "resources/list":
        reply(id, result: ["resources": listResources()])
    case "resources/templates/list":
        reply(id, result: ["resourceTemplates": [[
            "uriTemplate": resourcePrefix + "{id}",
            "name": "Meeting",
            "description": "One recorded meeting as Markdown: note, your bullets, transcript.",
            "mimeType": "text/markdown",
        ]]])
    case "resources/read":
        if let uri = params["uri"] as? String, let result = readResource(uri) {
            reply(id, result: result)
        } else {
            fail(id, code: -32002, "Resource not found")
        }
    default:
        fail(id, code: -32601, "Method not found: \(method)")
    }
}

log("ready · \(store.root.path)")
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        log("unparseable line")
        continue
    }
    handle(object)
}
log("stdin closed · exiting")
