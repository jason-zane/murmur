import FluidAudio
import Foundation

// murmur-models — fetch or inspect the on-device models Murmur can use.
//
// A developer tool, not part of the app bundle. The app downloads the same models from
// Settings; this exists so a fresh machine (or CI) can pre-seed them from a terminal and
// so a download can be watched with real progress output.
//
//   murmur-models status
//   murmur-models download parakeet|speakers|all

enum Kind: String, CaseIterable {
    case parakeet, speakers

    var label: String {
        switch self {
        case .parakeet: "Parakeet TDT v3 (~470 MB)"
        case .speakers: "Speaker separation — pyannote segmentation + WeSpeaker embeddings (~35 MB)"
        }
    }

    /// Filesystem evidence, matching what the app checks.
    var isDownloaded: Bool {
        let models = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
        switch self {
        case .parakeet:
            return FileManager.default.fileExists(atPath: models.appendingPathComponent("parakeet-tdt-0.6b-v3/Encoder.mlmodelc").path)
        case .speakers:
            let dir = DiarizerModels.defaultModelsDirectory()
            return FileManager.default.fileExists(atPath: dir.appendingPathComponent(ModelNames.Diarizer.segmentationFile).path)
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent(ModelNames.Diarizer.embeddingFile).path)
        }
    }

    func download() async throws {
        let started = Date()
        switch self {
        case .parakeet:
            _ = try await AsrModels.downloadAndLoad(version: .v3, encoderPrecision: .int8)
        case .speakers:
            _ = try await DiarizerModels.downloadIfNeeded()
        }
        print("  ready in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
    }
}

func status() {
    for kind in Kind.allCases {
        print("\(kind.isDownloaded ? "✓" : "·") \(kind.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(kind.label)")
    }
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "status", nil:
    status()
case "download":
    let which = args.dropFirst().first ?? "all"
    let kinds: [Kind] = which == "all" ? Kind.allCases : (Kind(rawValue: which).map { [$0] } ?? [])
    guard !kinds.isEmpty else {
        FileHandle.standardError.write("unknown model '\(which)'; one of: \(Kind.allCases.map(\.rawValue).joined(separator: ", ")), all\n".data(using: .utf8)!)
        exit(2)
    }
    for kind in kinds {
        if kind.isDownloaded {
            print("✓ \(kind.rawValue) already on disk")
            continue
        }
        print("↓ \(kind.label)")
        do { try await kind.download() } catch {
            FileHandle.standardError.write("  failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
    status()
default:
    print("usage: murmur-models [status | download parakeet|speakers|all]")
    exit(2)
}
