// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")
    ],
    targets: [
        .target(
            name: "MurmurDictionary",
            path: "Sources/MurmurDictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Session model and file store, shared by the app and the MCP server. Foundation and CryptoKit only: the MCP process must start fast and must not link AppKit.
        .target(
            name: "MurmurSessions",
            path: "Sources/MurmurSessions",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Murmur",
            dependencies: [
                "MurmurDictionary",
                "MurmurSessions",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Murmur",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Local stdio MCP server. Claude Desktop spawns it; it reads the session store and
        // answers over stdin/stdout. Connected clients decide which text reaches their AI provider.
        .executableTarget(
            name: "murmur-mcp",
            dependencies: ["MurmurMCPServer"],
            path: "Sources/MurmurMCP",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(name: "MurmurMCPServer", dependencies: ["MurmurSessions"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        // Developer tool: pre-seed or inspect the on-device models from a terminal.
        .executableTarget(
            name: "murmur-models",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/MurmurModels",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MurmurDictionaryTests",
            dependencies: ["MurmurDictionary"],
            path: "Tests/MurmurDictionaryTests",
            resources: [.copy("dictionary-test-vectors.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MurmurSessionsTests",
            dependencies: ["MurmurSessions"],
            path: "Tests/MurmurSessionsTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "MurmurMCPServerTests", dependencies: ["MurmurMCPServer", "MurmurSessions"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "MurmurAppTests", dependencies: ["Murmur", "MurmurSessions"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
