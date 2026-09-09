import Foundation
import Testing
import MurmurSessions
@testable import MurmurMCPServer

@MainActor
@Suite struct MCPServerTests {
    private func request(_ server: MCPServer, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        let response = try #require(server.respond(to: data))
        return try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
    }
    private func fixture() throws -> (SessionStore, MeetingSession, MCPServer) {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("murmur-mcp-test-\(UUID())"))
        let session = try store.createNote(title: "Product review")
        try store.append((0..<7).map { TranscriptSegment(start: Double($0 * 10), end: Double($0 * 10 + 5), source: .call, speaker: "Alex", text: "Decision \($0)") }, to: session.id)
        let server = MCPServer(store: store)
        _ = try request(server, "initialize", ["protocolVersion": "2025-06-18"])
        return (store, session, server)
    }
    @Test func protocolNegotiatesAndRejectsMalformedMessages() throws {
        let (store, _, server) = try fixture()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let initResponse = try request(server, "initialize", ["protocolVersion": "2025-06-18"])
        #expect((initResponse["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18")
        let bad = try #require(server.respond(to: Data("{".utf8)))
        let object = try #require(JSONSerialization.jsonObject(with: bad) as? [String: Any])
        #expect((object["error"] as? [String: Any])?["code"] as? Int == -32700)
        #expect(server.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)) == nil)
        #expect((try request(server, "unknown")["error"] as? [String: Any])?["code"] as? Int == -32601)
    }
    @Test func paginationAndInvalidInputs() throws {
        let (store, session, server) = try fixture()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let response = try request(server, "tools/call", ["name": "get_transcript", "arguments": ["id": session.id, "offset": 3, "limit": 3]])
        let result = try #require(response["result"] as? [String: Any])
        let output = try #require(result["structuredContent"] as? [String: Any])
        #expect(output["next_offset"] as? Int == 6)
        #expect(output["total"] as? Int == 7)
        for invalid: Any in [-1, 0, 1.5, true, "ten", 100_000] {
            let r = try request(server, "tools/call", ["name": "list_sessions", "arguments": ["limit": invalid]])
            #expect((r["result"] as? [String: Any])?["isError"] as? Bool == true)
        }
        let r = try request(server, "tools/call", ["name": "get_session", "arguments": ["id": "../outside"]])
        #expect((r["result"] as? [String: Any])?["isError"] as? Bool == true)
    }
    @Test func readOnlyByDefaultAndRevisionedWritesWhenEnabled() throws {
        let (store, session, server) = try fixture()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let denied = try request(server, "tools/call", ["name": "save_summary", "arguments": ["id": session.id, "text": "Summary", "expected_version": 0]])
        #expect(denied["error"] != nil)
        let writer = MCPServer(store: store, allowWrites: true)
        _ = try request(writer, "initialize", ["protocolVersion": "2025-11-25"])
        let args: [String: Any] = ["name": "save_summary", "arguments": ["id": session.id, "text": "## Summary\nA decision.", "expected_version": 0]]
        let saved = try request(writer, "tools/call", args)
        #expect((saved["result"] as? [String: Any])?["isError"] == nil)
        let stale = try request(writer, "tools/call", args)
        #expect((stale["result"] as? [String: Any])?["isError"] as? Bool == true)
        #expect(store.noteVersion(for: session.id) == 1)
        let search = try request(server, "tools/call", ["name": "search", "arguments": ["query": "A decision"]])
        #expect(((search["result"] as? [String: Any])?["structuredContent"] as? [String: Any])?["count"] as? Int == 1)
    }
    @Test func resourcesAndPromptsExposeMeetingContext() throws {
        let (store, session, server) = try fixture()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let resource = try request(server, "resources/read", ["uri": "murmur://sessions/\(session.id)"])
        #expect(resource["result"] != nil)
        let prompt = try request(server, "prompts/get", ["name": "summarize_meeting", "arguments": ["id": session.id]])
        #expect(prompt["result"] != nil)
        let missing = try request(server, "resources/read", ["uri": "murmur://sessions/../../outside"])
        #expect(missing["error"] != nil)
    }
}
