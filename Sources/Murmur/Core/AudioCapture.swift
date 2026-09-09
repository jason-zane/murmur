import AVFoundation
import CoreAudio
import CoreMedia
import Foundation
import Synchronization

enum CaptureError: LocalizedError {
    case noInputFormat
    case couldNotStart
    var errorDescription: String? {
        switch self {
        case .noInputFormat: "No usable microphone is connected. Check System Settings ▸ Sound ▸ Input."
        case .couldNotStart: "The microphone could not start. Check its connection and try again."
        }
    }
}

protocol DictationAudioCapturing: AnyObject, Sendable {
    func start(outputFormat: AVAudioFormat,
               onBuffer: @escaping @Sendable (AudioChunk) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void) async throws
    func stop()
}

/// Input-only capture. AVAudioEngine's duplex graph repeatedly stopped delivering AirPods
/// buffers after about 85 ms when Bluetooth changed its format between recordings.
/// AVCaptureSession owns input-device negotiation; conversion follows each buffer's actual
/// format. All session operations and buffer handling share one queue, never the UI thread.
final class AudioCapture: NSObject, DictationAudioCapturing, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jasonhunt.murmur.microphone", qos: .userInitiated)
    private let activeID = Mutex<UUID?>(nil)
    // Only accessed on queue. activeID is the synchronous cancellation boundary.
    private var session: AVCaptureSession?
    private var sessionID: UUID?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var onBuffer: (@Sendable (AudioChunk) -> Void)?
    private var onLevel: (@Sendable (Float) -> Void)?

    func start(
        outputFormat: AVAudioFormat,
        onBuffer: @escaping @Sendable (AudioChunk) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        let id = UUID()
        activeID.withLock { $0 = id }
        // AVAudioFormat is immutable here and confined to queue once handed off.
        let format = outputFormat
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    self.stopSession()
                    guard self.activeID.withLock({ $0 == id }) else { throw CancellationError() }
                    guard let device = AVCaptureDevice.default(for: .audio) else { throw CaptureError.noInputFormat }
                    let session = AVCaptureSession()
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioDataOutput()
                    guard session.canAddInput(input), session.canAddOutput(output) else { throw CaptureError.couldNotStart }
                    session.addInput(input)
                    session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    self.session = session
                    self.sessionID = id
                    self.outputFormat = format
                    self.onBuffer = onBuffer
                    self.onLevel = onLevel
                    session.startRunning()
                    guard self.activeID.withLock({ $0 == id }) else {
                        self.stopSession()
                        throw CancellationError()
                    }
                    guard session.isRunning else { throw CaptureError.couldNotStart }
                    Log.audio.info("microphone capture started: \(device.localizedName, privacy: .public)")
                    continuation.resume()
                } catch {
                    self.stopSession()
                    continuation.resume(throwing: error)
                }
            }
        }
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
        activeID.withLock { $0 = nil }
        queue.async { self.stopSession() }
    }

    private func stopSession() {
        session?.stopRunning()
        for output in session?.outputs ?? [] {
            (output as? AVCaptureAudioDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
        }
        session = nil
        sessionID = nil
        converter = nil
        inputFormat = nil
        onBuffer = nil
        onLevel = nil
    }

    // MARK: - Capture queue

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let sessionID, activeID.withLock({ $0 == sessionID }),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else { return }
        handle(buffer)
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        onLevel?(Self.rms(of: buffer))

        guard let outputFormat else { return }

        if inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = buffer.format == outputFormat ? nil : AVAudioConverter(from: buffer.format, to: outputFormat)
            Log.audio.info("microphone format: \(buffer.format.sampleRate) Hz → \(outputFormat.sampleRate) Hz")
        }

        // captureOutput already copied CoreMedia's storage into this owned buffer.
        guard let converter else {
            if buffer.format == outputFormat {
                onBuffer?(AudioChunk(buffer: buffer))
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
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        for frame in 0..<count {
            let index = frame * stride
            let sample: Float
            if let channel = buffer.floatChannelData?[0] { sample = channel[index] }
            else if let channel = buffer.int16ChannelData?[0] { sample = Float(channel[index]) / 32_768 }
            else if let channel = buffer.int32ChannelData?[0] { sample = Float(channel[index]) / 2_147_483_648 }
            else { return 0 }
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()

        // Map roughly -50…0 dBFS onto 0…1 so quiet speech still moves the meter.
        let db = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (db + 50) / 50))
    }
}
