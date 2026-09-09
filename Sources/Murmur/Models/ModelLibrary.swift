import FluidAudio
import Foundation
import Observation

/// Which optional on-device models exist, whether they are on disk, and how to fetch them.
///
/// Every download is explicit — a button in Settings or the `murmur-models` tool — never a
/// side effect of starting a meeting. Presence is judged from the filesystem so that a
/// fresh launch reports the truth without loading anything.
enum ModelKind: String, CaseIterable, Identifiable, Sendable {
    case parakeet
    case speakers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parakeet: "Parakeet"
        case .speakers: "Speaker separation"
        }
    }

    var detail: String {
        switch self {
        case .parakeet:
            "NVIDIA's Parakeet TDT v3 on the Neural Engine. More accurate than Apple on English; "
                + "batch, so text lands a sentence or two behind."
        case .speakers:
            "Tells the people on the other side of a call apart — Speaker 1, Speaker 2 — so "
                + "you can name them afterwards. pyannote segmentation and WeSpeaker embeddings."
        }
    }

    var sizeHint: String {
        switch self {
        case .parakeet: "~470 MB"
        case .speakers: "~35 MB"
        }
    }

    private static var modelsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }

    var isDownloaded: Bool {
        switch self {
        case .parakeet:
            return ParakeetModels.isDownloaded
        case .speakers:
            let dir = DiarizerModels.defaultModelsDirectory()
            return FileManager.default.fileExists(atPath: dir.appendingPathComponent(ModelNames.Diarizer.segmentationFile).path)
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent(ModelNames.Diarizer.embeddingFile).path)
        }
    }
}

@MainActor
@Observable
final class ModelLibrary {
    static let shared = ModelLibrary()

    /// 0…1 while a download is running; absent otherwise.
    private(set) var progress: [ModelKind: Double] = [:]
    private(set) var errors: [ModelKind: String] = [:]

    func isDownloading(_ kind: ModelKind) -> Bool { progress[kind] != nil }

    func download(_ kind: ModelKind) {
        guard progress[kind] == nil else { return }
        progress[kind] = 0
        errors[kind] = nil
        Log.speech.info("model download started: \(kind.rawValue, privacy: .public)")
        Task {
            let started = Date()
            do {
                let report: ProgressHandler = { [weak self] p in
                    Task { @MainActor in self?.progress[kind] = p.fractionCompleted }
                }
                switch kind {
                case .parakeet:
                    // Loads too, so the first meeting after the download does not pay for it.
                    _ = try await ParakeetModels.shared.manager(progress: report)
                case .speakers:
                    _ = try await DiarizerModels.downloadIfNeeded(progressHandler: report)
                }
                Log.speech.info("model download finished: \(kind.rawValue, privacy: .public) in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
            } catch {
                errors[kind] = error.localizedDescription
                Log.speech.error("model download failed: \(kind.rawValue, privacy: .public) — \(error.localizedDescription)")
            }
            progress[kind] = nil
        }
    }
}
