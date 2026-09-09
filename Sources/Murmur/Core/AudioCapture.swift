import AVFoundation
import CoreAudio
import Foundation

/// Microphone capture with on-the-fly conversion to whatever format the speech engine wants.
///
/// The tap runs on a real-time audio thread, so everything it touches lives behind
/// `nonisolated(unsafe)` and is only ever mutated from that one thread.
enum CaptureError: LocalizedError {
    case noInputFormat
    var errorDescription: String? {
        "No usable input format on the current microphone. Check System Settings ▸ Sound ▸ Input."
    }
}

final class AudioCapture: @unchecked Sendable {
    /// Recreated for every capture, never reused.
    ///
    /// `AVAudioEngine.inputNode` binds to a device the first time it is touched and then
    /// keeps it. A single long-lived engine therefore latches onto whatever was the default
    /// input at first launch — a Bluetooth headset, say — and goes on using it after that
    /// headset disconnects or the user changes source in System Settings. Building a fresh
    /// engine per dictation means each one starts from the current default.
    private nonisolated(unsafe) var engine = AVAudioEngine()
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private nonisolated(unsafe) var outputFormat: AVAudioFormat?
    private var isRunning = false

    /// Called on the audio thread with each converted buffer.
    private nonisolated(unsafe) var onBuffer: (@Sendable (AudioChunk) -> Void)?
    /// Called on the audio thread with a 0…1 RMS level, for the HUD waveform.
    private nonisolated(unsafe) var onLevel: (@Sendable (Float) -> Void)?

    func start(
        outputFormat: AVAudioFormat,
        onBuffer: @escaping @Sendable (AudioChunk) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        guard !isRunning else { return }

        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.outputFormat = outputFormat

        // A fresh engine binds to the system default input at creation, which is the whole
        // fix for following device changes. Do NOT also set the device explicitly on the
        // input unit: that kicks off an asynchronous graph reconfiguration, and the format
        // read on the next line comes back stale (44.1k against 48k hardware). The tap
        // then fails to install — "Failed to create tap, config change pending!" — while
        // `engine.start()` still succeeds. Capture logs as started and no buffer ever
        // arrives, so the speech engine has nothing to finalize and hangs on stop.
        engine = AVAudioEngine()
        let input = engine.inputNode

        let nativeFormat = input.outputFormat(forBus: 0)

        // Fail loudly rather than start a capture that can't produce audio. A degenerate
        // format here is exactly the symptom of the graph being mid-reconfiguration.
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw CaptureError.noInputFormat
        }

        converter = nativeFormat == outputFormat
            ? nil
            : AVAudioConverter(from: nativeFormat, to: outputFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        Log.audio.info("capture started — native \(nativeFormat.sampleRate)Hz → engine \(outputFormat.sampleRate)Hz")
    }

    /// The system's current default input, for display in Settings and in the log.
    static var currentInputName: String? {
        guard let id = defaultInputDeviceID() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        converter = nil
        onBuffer = nil
        onLevel = nil
        Log.audio.info("capture stopped")
    }

    // MARK: - Audio thread

    private func handle(_ buffer: AVAudioPCMBuffer) {
        onLevel?(Self.rms(of: buffer))

        guard let outputFormat else { return }

        // AVAudioEngine reuses the tap's buffer as soon as this returns, so the engine
        // must never see it directly — copy when no conversion would otherwise allocate.
        guard let converter else {
            if let copy = Self.copy(buffer) {
                onBuffer?(AudioChunk(buffer: copy))
            }
            return
        }

        // Output frame count scales with the sample-rate ratio; round up so we never clip.
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        // The input block runs synchronously inside `convert`, on this thread.
        nonisolated(unsafe) let input = buffer
        let consumed = Latch()
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            guard !consumed.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return input
        }

        if let error {
            Log.audio.error("conversion failed: \(error.localizedDescription)")
            return
        }
        guard status != .error, converted.frameLength > 0 else { return }
        onBuffer?(AudioChunk(buffer: converted))
    }

    /// Deep-copies a tap buffer into storage we own.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
        else { return nil }

        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else {
            return nil
        }

        return copy
    }

    /// One-shot flag. Only touched from the audio thread inside a synchronous call.
    private final class Latch: @unchecked Sendable {
        private var fired = false
        /// - Returns: the value *before* this call, then latches to `true`.
        func take() -> Bool {
            defer { fired = true }
            return fired
        }
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<count {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()

        // Map roughly -50…0 dBFS onto 0…1 so quiet speech still moves the meter.
        let db = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (db + 50) / 50))
    }
}
