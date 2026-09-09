import Foundation
import MurmurSessions

/// Configuration is merged only after a complete parse. A malformed client config is an
/// error, never permission to silently replace somebody's other connections.
enum ClaudeDesktopIntegration {
    static var configURL: URL {
        if let root = PreviewEnvironment.root { return root.appendingPathComponent("claude_desktop_config.json") }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude/claude_desktop_config.json")
    }
    static var serverPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/murmur-mcp").path
    }
    static var isConfigured: Bool {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any],
              let murmur = servers["murmur"] as? [String: Any] else { return false }
        return murmur["command"] as? String == serverPath
    }
    static var allowsWrites: Bool {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any],
              let murmur = servers["murmur"] as? [String: Any] else { return false }
        return (murmur["args"] as? [String])?.contains("--allow-writes") == true
    }
    static var snippet: String { snippet(allowWrites: false) }
    static func snippet(allowWrites: Bool) -> String {
        let object: [String: Any] = ["mcpServers": ["murmur": configuration(allowWrites: allowWrites)]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    private static func configuration(allowWrites: Bool, serverPath: String = serverPath) -> [String: Any] {
        ["command": serverPath, "args": allowWrites ? ["--allow-writes"] : []]
    }
    static func configure(allowWrites: Bool = false, configURL: URL = configURL, serverPath: String = serverPath) throws {
        guard FileManager.default.isExecutableFile(atPath: serverPath) else { throw IntegrationError("Install Voice Notes in Applications before connecting it.") }
        var object: [String: Any] = [:]
        var original: Data?
        if FileManager.default.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw IntegrationError("Claude's configuration isn't a JSON object. It has been left unchanged.") }
            object = parsed; original = data
        }
        if let servers = object["mcpServers"], !(servers is [String: Any]) { throw IntegrationError("Claude's mcpServers setting is invalid. It has been left unchanged.") }
        var servers = object["mcpServers"] as? [String: Any] ?? [:]
        servers["murmur"] = configuration(allowWrites: allowWrites, serverPath: serverPath)
        object["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let original {
            let backup = configURL.deletingLastPathComponent().appendingPathComponent("claude_config.before-murmur-\(UUID().uuidString.prefix(8)).json")
            try original.write(to: backup, options: .atomic)
        }
        try data.write(to: configURL, options: .atomic)
    }
    struct IntegrationError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
