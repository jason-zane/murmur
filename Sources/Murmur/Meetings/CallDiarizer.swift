import AVFoundation
import FluidAudio
import Foundation

/// Who is speaking on the far side of a call, ten seconds at a time.
///
/// The mic is always "You", so diarization only has to sort out the call stream. Audio is
/// gathered into 10 s chunks and run through FluidAudio's segmentation + embedding models;
/// the manager keeps a speaker database across chunks, so a voice heard in minute two is
/// still the same speaker in minute forty. Labels are ordinal by first appearance —
/// "Speaker 1", "Speaker 2" — and the user renames them afterwards in the session view.
///
/// Nothing here touches disk. Spans live in memory for the session and the controller
/// stamps them onto transcript segments as they finalise.
actor CallDiarizer {
    struct Span: Sendable {
        let start: TimeInterval
        let end: TimeInterval
        let speaker: String
    }

    private let manager = DiarizerManager(config: DiarizerConfig(
        clusteringThreshold: 0.7,
        minSpeechDuration: 0.6,
        minSilenceGap: 0.3,
        chunkDuration: 10
    ))
    private let converter = AudioConverter()
    private var buffer: [Float] = []
    private var bufferStart: TimeInterval = 0
    private var spans: [Span] = []
    private var names: [String: String] = [:]
    private var isReady = false

    private static let sampleRate = 16_000
    private static let chunkSeconds: TimeInterval = 10
    /// Below this the chunk is skipped: no one is talking, and the models would only
    /// hallucinate a speaker out of room tone.
    private static let silenceFloorDB: Float = -55

    /// Session time through which speaker spans are settled. Segments ending before this
    /// can be labelled; later ones wait for the next chunk.
    private(set) var coveredThrough: TimeInterval = 0

    /// Loads the models from disk. Throws if they are not there; never downloads.
    func prepare() async throws {
        let models = try await DiarizerModels.load()
        manager.initialize(models: models)
        isReady = true
    }

    /// Feeds call audio. Returns the new `coveredThrough` when a chunk was completed,
    /// nil otherwise, so the caller only wakes when there is something to label.
    func feed(_ chunk: AudioChunk) -> TimeInterval? {
        guard chunk.buffer.frameLength > 0 else { return nil }
        guard isReady else {
            // Models may still be preparing while transcription is already live. Keep
            // the audio timeline honest; early speech simply has no inferred speaker.
            bufferStart += Double(chunk.buffer.frameLength) / chunk.buffer.format.sampleRate
            coveredThrough = bufferStart
            return coveredThrough
        }
        let samples: [Float]
        do { samples = try converter.resampleBuffer(chunk.buffer) } catch {
            Log.speech.error("diarizer: conversion failed — \(error.localizedDescription)")
            return nil
        }
        buffer.append(contentsOf: samples)
        let chunkSamples = Int(Self.chunkSeconds) * Self.sampleRate
        guard buffer.count >= chunkSamples else { return nil }
        let slice = Array(buffer.prefix(chunkSamples))
        buffer.removeFirst(chunkSamples)
        run(slice, at: bufferStart)
        bufferStart += Self.chunkSeconds
        coveredThrough = bufferStart
        return coveredThrough
    }

    /// Runs whatever is left. Called once, at the end of the session.
    func flush() {
        guard isReady else { return }
        let seconds = Double(buffer.count) / Double(Self.sampleRate)
        if seconds >= 1.0 {
            run(buffer, at: bufferStart)
        }
        coveredThrough = bufferStart + seconds
        buffer.removeAll()
    }

    /// The speaker who held the floor for most of the interval — or, for a very short
    /// line, whoever was speaking nearest to it.
    func speaker(for start: TimeInterval, to end: TimeInterval) -> String? {
        var share: [String: TimeInterval] = [:]
        for span in spans {
            let overlap = min(end, span.end) - max(start, span.start)
            if overlap > 0 { share[span.speaker, default: 0] += overlap }
        }
        if let best = share.max(by: { $0.value < $1.value }) { return best.key }
        // No overlap: the nearest span within a second, if any.
        let mid = (start + end) / 2
        return spans
            .map { ($0, min(abs($0.start - mid), abs($0.end - mid))) }
            .filter { $0.1 <= 1.0 }
            .min { $0.1 < $1.1 }?
            .0.speaker
    }

    var speakerCount: Int { names.count }

    // MARK: - Private

    private func run(_ samples: [Float], at time: TimeInterval) {
        var sum: Float = 0
        for s in samples { sum += s * s }
        let db = 20 * log10(max((sum / Float(max(samples.count, 1))).squareRoot(), 1e-7))
        guard db > Self.silenceFloorDB else { return }

        do {
            let result = try manager.performCompleteDiarization(samples, sampleRate: Self.sampleRate, atTime: time)
            for segment in result.segments where !segment.speakerId.isEmpty {
                let name = names[segment.speakerId] ?? {
                    let label = "Speaker \(names.count + 1)"
                    names[segment.speakerId] = label
                    return label
                }()
                spans.append(Span(
                    start: TimeInterval(segment.startTimeSeconds),
                    end: TimeInterval(segment.endTimeSeconds),
                    speaker: name
                ))
            }
        } catch {
            Log.speech.error("diarizer: chunk at \(time, format: .fixed(precision: 1))s failed — \(error.localizedDescription)")
        }
    }
}
