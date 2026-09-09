import AVFoundation
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
//   murmur-models diarize <file.wav>     # sanity-check the speaker models on a recording

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
case "diarize":
    guard let path = args.dropFirst().first else {
        print("usage: murmur-models diarize <file.wav>")
        exit(2)
    }
    do {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let converter = AudioConverter()
        let samples = try converter.resampleAudioFile(URL(fileURLWithPath: path))
        let seconds = Double(samples.count) / 16_000
        print("audio: \(String(format: "%.1f", seconds))s at \(Int(file.fileFormat.sampleRate)) Hz → 16 kHz mono")
        let models = try await DiarizerModels.load()
        let manager = DiarizerManager(config: DiarizerConfig(minSpeechDuration: 0.6, minSilenceGap: 0.3, chunkDuration: 10))
        manager.initialize(models: models)
        // Same shape as the app: 10 s chunks, speaker database carried across them.
        let chunk = 160_000
        var names: [String: String] = [:]
        var offset = 0
        let started = Date()
        while offset < samples.count {
            let slice = Array(samples[offset..<min(offset + chunk, samples.count)])
            let result = try manager.performCompleteDiarization(slice, sampleRate: 16_000, atTime: Double(offset) / 16_000)
            for seg in result.segments where !seg.speakerId.isEmpty {
                let name = names[seg.speakerId] ?? { let n = "Speaker \(names.count + 1)"; names[seg.speakerId] = n; return n }()
                print(String(format: "  %6.1f – %6.1f  %@", seg.startTimeSeconds, seg.endTimeSeconds, name))
            }
            offset += chunk
        }
        print("\(names.count) speaker(s) in \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
    } catch {
        FileHandle.standardError.write("failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
default:
    print("usage: murmur-models [status | download parakeet|speakers|all | diarize <file.wav>]")
    exit(2)
}
