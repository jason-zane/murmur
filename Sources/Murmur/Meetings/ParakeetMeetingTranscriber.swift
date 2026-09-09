import AVFoundation
import FluidAudio
import Foundation
import MurmurSessions

/// Parakeet for meetings: batch windows cut at pauses.
///
/// Parakeet transcribes a buffer, not a stream. For dictation that's a non-issue — the
/// buffer is the utterance. For an hour-long call, the audio is cut into windows at natural
/// pauses (0.8 s of quiet after speech) or at 30 s, whichever comes first, and each window
/// is transcribed in order as the next one records. Windows with no speech are dropped, so
/// silence costs nothing. Live partials are not produced; the notepad's live view shows
/// finalised windows instead, a sentence or two behind.
///
/// Only chosen when the models are on disk. FluidAudio's streaming EOU model would give true
/// live text, but it is a separate download and waits for permission.
actor ParakeetMeetingTranscriber: MeetingTranscriber {
    private let converter = AudioConverter()
    private var events: AsyncStream<MeetingTranscriptEvent>.Continuation?
    private var source: AudioStreamSource = .call
    private var offset: TimeInterval = 0

    private var window: [Float] = []
    private var windowStart: TimeInterval = 0
    private var fedSeconds: TimeInterval = 0
    private var silenceSamples = 0
    private var windowHasSpeech = false
    private var previous: Task<Void, Never>?

    private static let sampleRate = 16_000
    private static let maxWindow = 30.0
    private static let pauseToCut = 0.8
    private static let minWindow = 1.5
    private static let silentWindowDrop = 12.0
    /// dBFS above which a chunk counts as speech. Conservative: false positives only cost a
    /// window that transcribes to nothing.
    private static let speechFloorDB: Float = -42

    func preferredInputFormat() async -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(Self.sampleRate), channels: 1, interleaved: false)
    }

    func start(source: AudioStreamSource, offset: TimeInterval) async throws -> AsyncStream<MeetingTranscriptEvent> {
        self.source = source
        self.offset = offset
        window.removeAll(keepingCapacity: true)
        windowStart = 0
        fedSeconds = 0
        silenceSamples = 0
        windowHasSpeech = false
        _ = try await ParakeetModels.shared.manager()
        let (stream, continuation) = AsyncStream<MeetingTranscriptEvent>.makeStream()
        events = continuation
        Log.speech.info("meeting transcriber (Parakeet) started for \(source.rawValue, privacy: .public)")
        return stream
    }

    func feed(_ chunk: AudioChunk) async {
        guard chunk.buffer.frameLength > 0 else { return }
        let samples: [Float]
        do { samples = try converter.resampleBuffer(chunk.buffer) } catch {
            Log.speech.error("Parakeet meeting: conversion failed — \(error.localizedDescription)")
            return
        }
        guard !samples.isEmpty else { return }

        var sum: Float = 0
        for s in samples { sum += s * s }
        let db = 20 * log10(max((sum / Float(samples.count)).squareRoot(), 1e-7))
        if db > Self.speechFloorDB {
            silenceSamples = 0
            windowHasSpeech = true
        } else {
            silenceSamples += samples.count
        }

        window.append(contentsOf: samples)
        fedSeconds += Double(samples.count) / Double(Self.sampleRate)
        let windowSeconds = fedSeconds - windowStart
        let pauseSeconds = Double(silenceSamples) / Double(Self.sampleRate)

        if windowHasSpeech {
            if (pauseSeconds >= Self.pauseToCut && windowSeconds >= Self.minWindow) || windowSeconds >= Self.maxWindow {
                cut()
            }
        } else if windowSeconds >= Self.silentWindowDrop {
            // Nothing said. Drop it rather than transcribe silence.
            window.removeAll(keepingCapacity: true)
            windowStart = fedSeconds
            silenceSamples = 0
        }
    }

    func finish() async {
        if windowHasSpeech, !window.isEmpty { cut() }
        await previous?.value
        events?.finish()
        events = nil
    }

    private func cut() {
        let samples = window
        let start = windowStart
        let end = fedSeconds
        window.removeAll(keepingCapacity: true)
        windowStart = fedSeconds
        silenceSamples = 0
        windowHasSpeech = false
        guard samples.count >= 1_600 else { return }

        // Chained, so windows are emitted in order even when one takes longer.
        let earlier = previous
        previous = Task { [weak self] in
            await earlier?.value
            await self?.transcribe(samples, start: start, end: end)
        }
    }

    private func transcribe(_ samples: [Float], start: TimeInterval, end: TimeInterval) async {
        do {
            let manager = try await ParakeetModels.shared.manager()
            var state = try TdtDecoderState()
            let result = try await manager.transcribe(samples, decoderState: &state)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            events?.yield(.final(TranscriptSegment(start: offset + start, end: offset + end, source: source, text: text)))
        } catch {
            Log.speech.error("Parakeet meeting window failed: \(error.localizedDescription)")
        }
    }
}
