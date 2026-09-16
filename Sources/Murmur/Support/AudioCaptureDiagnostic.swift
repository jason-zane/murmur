#if DEBUG
import AppKit
import AVFoundation
import Synchronization
import MurmurSessions

/// Opt-in hardware smoke test using the installed app's real TCC identity. Measures
/// buffers only: no audio or transcript is retained, and no personal note is created.
@MainActor
enum AudioCaptureDiagnostic {
    static func run() async {
        let microphone = AudioCapture()
        let capture = SystemAudioCapture()
        let measurements = Mutex((buffers: 0, frames: 0, peak: Float(0)))
        do {
            var format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let browserTest = ProcessInfo.processInfo.arguments.contains("--browser-audio")
            let engine = browserTest ? AppleMeetingTranscriber() : nil
            let (audio, continuation) = AsyncStream<AudioChunk>.makeStream()
            var feed: Task<Void, Never>?
            var results: Task<Void, Never>?
            if let engine {
                let events = try await engine.start(source: .call, offset: 0)
                guard let preferred = await engine.preferredInputFormat() else { throw TranscriptionError.noAudioFormat }
                format = preferred
                feed = Task { for await chunk in audio { await engine.feed(chunk) } }
                results = Task {
                    for await event in events {
                        if case .final(let segment) = event { print("Call transcript: \(segment.text)") }
                    }
                }
            }
            let captureFormat = format
            try await microphone.start(outputFormat: captureFormat, onBuffer: { _ in }, onLevel: { _ in })
            try await AsyncDeadline.run(for: .seconds(15)) {
                try capture.start(outputFormat: captureFormat, onBuffer: { chunk in
                    if browserTest { continuation.yield(chunk) }
                    let frames = Int(chunk.buffer.frameLength)
                    var peak: Float = 0
                    if let samples = chunk.buffer.floatChannelData?[0] {
                        for i in 0..<frames { peak = max(peak, abs(samples[i])) }
                    }
                    if let samples = chunk.buffer.int16ChannelData?[0] {
                        for i in 0..<frames { peak = max(peak, abs(Float(samples[i])) / 32_768) }
                    }
                    measurements.withLock {
                        $0.buffers += 1
                        $0.frames += frames
                        $0.peak = max($0.peak, peak)
                    }
                }, onLevel: { _ in })
            }
            print("Audio diagnostic ready")
            if browserTest {
                try await Task.sleep(for: .seconds(25))
            } else {
                try await Task.sleep(for: .seconds(2))
                let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: true)
                sound?.play()
                try await Task.sleep(for: .seconds(5))
            }
            microphone.stop()
            await Task.detached { capture.stop() }.value
            continuation.finish()
            await feed?.value
            await engine?.finish()
            await results?.value
            let result = measurements.withLock { ["buffers": Double($0.buffers), "frames": Double($0.frames), "peak": Double($0.peak)] }
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            microphone.stop()
            Task.detached { capture.stop() }
            print("Audio diagnostic failed: \(error.localizedDescription)")
        }
        NSApp.terminate(nil)
    }
}
#endif
