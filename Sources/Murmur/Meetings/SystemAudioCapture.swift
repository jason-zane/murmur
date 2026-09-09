import AVFoundation
import CoreAudio
import Foundation

/// Hears what the Mac is playing — the far side of a call — without a bot, a virtual audio
/// device, or Screen Recording permission.
///
/// Built on Core Audio process taps (macOS 14.2+). A global tap mixes every process's
/// output down to mono, an aggregate device wraps the tap so it can be read through an
/// ordinary IO proc, and the samples are converted to whatever the transcriber asked for.
/// ScreenCaptureKit could do the same job, but it is screen-recording-shaped: it wants the
/// Screen Recording grant, lights the menu bar indicator, and captures notifications and
/// music alongside the call. A tap is audio-only and asks only for Audio Recording.
///
/// Sibling to `AudioCapture`, not a mode of it. The two streams are never mixed: the mic is
/// you, the tap is everyone else, and that split is what makes speaker separation cheap.
final class SystemAudioCapture: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case tapCreationFailed(OSStatus)
        case noOutputDevice
        case aggregateCreationFailed(OSStatus)
        case ioProcFailed(OSStatus)
        case startFailed(OSStatus)
        case badFormat

        var errorDescription: String? {
            switch self {
            case .tapCreationFailed(let s): "Couldn't tap system audio (\(s)). Allow Audio Recording in System Settings ▸ Privacy & Security."
            case .noOutputDevice: "No output device to listen to."
            case .aggregateCreationFailed(let s): "Couldn't create the capture device (\(s))."
            case .ioProcFailed(let s): "Couldn't attach to the capture device (\(s))."
            case .startFailed(let s): "Couldn't start system audio capture (\(s))."
            case .badFormat: "System audio has an unusable format."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.jasonhunt.murmur.systemaudio", qos: .userInitiated)

    /// Remembered after the first successful tap. There is no public API to *ask* TCC about
    /// Audio Recording without triggering the prompt, so success is the only evidence.
    static var isKnownGranted: Bool {
        get { UserDefaults.standard.bool(forKey: "audioCapture.granted") }
        set { UserDefaults.standard.set(newValue, forKey: "audioCapture.granted") }
    }

    /// Provokes the Audio Recording consent dialog by creating and destroying a throwaway
    /// tap. **Never call this on the main thread**: `AudioHardwareCreateProcessTap` blocks
    /// its caller until the dialog is answered, and a blocked main thread is a frozen app —
    /// which is exactly how this was first discovered.
    static func requestPermission() async -> Bool {
        let granted = await Task.detached(priority: .userInitiated) { () -> Bool in
            let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
            description.uuid = UUID()
            description.isPrivate = true
            description.muteBehavior = .unmuted
            var tap = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(description, &tap)
            guard status == noErr, tap != kAudioObjectUnknown else {
                Log.audio.error("audio recording permission: tap creation failed (\(status))")
                return false
            }
            AudioHardwareDestroyProcessTap(tap)
            return true
        }.value
        if granted { isKnownGranted = true }
        return granted
    }

    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID: AudioDeviceID = AudioDeviceID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var tapFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var isRunning = false

    private nonisolated(unsafe) var onBuffer: (@Sendable (AudioChunk) -> Void)?
    private nonisolated(unsafe) var onLevel: (@Sendable (Float) -> Void)?

    /// The default output device at start. If it changes mid-session — AirPods connect —
    /// the tap follows on the next `restart()`; the controller listens for that.
    private(set) var outputDeviceUID: String?

    func start(
        outputFormat: AVAudioFormat,
        onBuffer: @escaping @Sendable (AudioChunk) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        guard !isRunning else { return }
        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.outputFormat = outputFormat

        // 1. A private, mono, global tap: every process's output, mixed down, invisible to
        //    other apps, and never muting what the user hears.
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr, tap != kAudioObjectUnknown else {
            throw CaptureError.tapCreationFailed(tapStatus)
        }
        tapID = tap

        // 2. The tap's own stream format, which is what the IO proc will hand us.
        guard var asbd: AudioStreamBasicDescription = Self.read(tap, kAudioTapPropertyFormat),
              let format = AVAudioFormat(streamDescription: &asbd) else {
            teardown()
            throw CaptureError.badFormat
        }
        tapFormat = format

        // 3. Wrap the tap in a private aggregate device anchored on the default output, so
        //    it can be read like any input device.
        guard let outputID: AudioDeviceID = Self.read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice),
              outputID != kAudioObjectUnknown,
              let outputUID = Self.readString(outputID, kAudioDevicePropertyDeviceUID) else {
            teardown()
            throw CaptureError.noOutputDevice
        }
        outputDeviceUID = outputUID

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Murmur call capture",
            kAudioAggregateDeviceUIDKey: "com.jasonhunt.murmur.capture." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var aggregate = AudioDeviceID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard aggregateStatus == noErr, aggregate != kAudioObjectUnknown else {
            teardown()
            throw CaptureError.aggregateCreationFailed(aggregateStatus)
        }
        aggregateID = aggregate

        converter = format == outputFormat ? nil : AVAudioConverter(from: format, to: outputFormat)

        // 4. An IO proc on the aggregate. Input buffers are the tap's mixdown.
        var proc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, queue) { [weak self] _, inInputData, _, _, _ in
            self?.handle(inInputData)
        }
        guard procStatus == noErr, let proc else {
            teardown()
            throw CaptureError.ioProcFailed(procStatus)
        }
        procID = proc

        let startStatus = AudioDeviceStart(aggregate, proc)
        guard startStatus == noErr else {
            teardown()
            throw CaptureError.startFailed(startStatus)
        }

        isRunning = true
        Self.isKnownGranted = true
        Log.audio.info("system audio capture started — tap \(format.sampleRate)Hz/\(format.channelCount)ch → \(outputFormat.sampleRate)Hz, output \(outputUID, privacy: .public)")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        teardown()
        onBuffer = nil
        onLevel = nil
        converter = nil
        Log.audio.info("system audio capture stopped")
    }

    /// Whether the default output device has moved away from the one the tap is anchored to.
    var outputDeviceChanged: Bool {
        guard let anchored = outputDeviceUID,
              let outputID: AudioDeviceID = Self.read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice),
              let current = Self.readString(outputID, kAudioDevicePropertyDeviceUID) else { return false }
        return current != anchored
    }

    // MARK: - IO

    private func handle(_ list: UnsafePointer<AudioBufferList>) {
        guard let tapFormat, let outputFormat else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, first.mDataByteSize > 0 else { return }
        let bytesPerFrame = Int(tapFormat.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return }
        let frames = AVAudioFrameCount(Int(first.mDataByteSize) / bytesPerFrame)
        guard frames > 0,
              let source = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: list, deallocator: nil) else { return }
        source.frameLength = frames

        onLevel?(Self.rms(of: source))

        guard let converter else {
            if let copy = Self.copy(source) { onBuffer?(AudioChunk(buffer: copy)) }
            return
        }

        let ratio = outputFormat.sampleRate / tapFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        nonisolated(unsafe) let input = source
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
            Log.audio.error("system audio conversion failed: \(error.localizedDescription)")
            return
        }
        guard status != .error, converted.frameLength > 0 else { return }
        onBuffer?(AudioChunk(buffer: converted))
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioDeviceID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        tapFormat = nil
    }

    // MARK: - Helpers

    private final class Latch: @unchecked Sendable {
        private var fired = false
        func take() -> Bool {
            defer { fired = true }
            return fired
        }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if let s = buffer.floatChannelData, let d = copy.floatChannelData {
            for c in 0..<channels { d[c].update(from: s[c], count: frames) }
        } else if let s = buffer.int16ChannelData, let d = copy.int16ChannelData {
            for c in 0..<channels { d[c].update(from: s[c], count: frames) }
        } else if let s = buffer.int32ChannelData, let d = copy.int32ChannelData {
            for c in 0..<channels { d[c].update(from: s[c], count: frames) }
        } else {
            return nil
        }
        return copy
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<count { sum += channel[i] * channel[i] }
        } else if let channel = buffer.int16ChannelData?[0] {
            for i in 0..<count {
                let v = Float(channel[i]) / 32768
                sum += v * v
            }
        } else {
            return 0
        }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (db + 50) / 50))
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
