import Foundation
import MurmurMCPServer
import Darwin

// One JSON-RPC message per line. stdout is exclusively protocol traffic.
let arguments = Set(CommandLine.arguments.dropFirst())
if arguments.contains("--help") {
    print("murmur-mcp [--allow-writes]\nLocal stdio MCP for Voice Notes. MURMUR_SESSIONS_DIR overrides the notes folder.")
    exit(0)
}
if !arguments.isSubset(of: ["--allow-writes"]) {
    FileHandle.standardError.write(Data("Unknown option. Use --help.\n".utf8))
    exit(2)
}
let server = MCPServer(allowWrites: arguments.contains("--allow-writes"))
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty else { continue }
    if let response = server.respond(to: Data(line.utf8)) {
        FileHandle.standardOutput.write(response)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
