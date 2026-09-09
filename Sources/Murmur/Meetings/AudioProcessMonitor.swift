import AppKit
import CoreAudio
import Foundation
import Observation

/// One process as Core Audio sees it: who it is, and whether it is currently pulling audio
/// in, pushing audio out, or both.
struct AudioProcessInfo: Sendable, Hashable, Identifiable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let isRunningInput: Bool
    let isRunningOutput: Bool

    var id: AudioObjectID { objectID }

    /// Input and output on one process is what a call looks like. Input alone is a voice
    /// memo, Siri or dictation; output alone is music.
    var isTwoWay: Bool { isRunningInput && isRunningOutput }
}

/// Watches which processes have the microphone open, by asking Core Audio directly.
///
/// This is the layer Granola doesn't have. `kAudioDevicePropertyDeviceIsRunningSomewhere`
/// only says that *some* process is using the mic. The process-object properties — present
/// since macOS 14.2 and verified in this machine's SDK — say *which* process, and whether it
/// also has an output stream running. That second bit is what separates a Zoom call from a
/// voice memo, and it is the single biggest source of false positives removed.
///
/// A property listener on the process list fires when processes come and go; the per-process
/// running state is polled every couple of seconds, because listeners on individual process
/// objects have proven unreliable across macOS versions and a two-second poll costs nothing.
@MainActor
@Observable
final class AudioProcessMonitor {
    private(set) var processes: [AudioProcessInfo] = []

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var listenerInstalled = false
    @ObservationIgnored private var listenerBlock: AudioObjectPropertyListenerBlock?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private static var listAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start(pollInterval: Duration = .seconds(2)) {
        guard pollTask == nil else { return }
        installListener()
        refresh()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                self?.refresh()
            }
        }
        Log.audio.info("process monitor started")
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if listenerInstalled, let listenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &Self.listAddress, .main, listenerBlock
            )
            listenerInstalled = false
        }
    }

    /// Re-reads every process object. Cheap: a handful of property reads.
    func refresh() {
        let ids = Self.processObjectIDs()
        var next: [AudioProcessInfo] = []
        next.reserveCapacity(ids.count)
        for id in ids {
            guard let pid: pid_t = Self.read(id, kAudioProcessPropertyPID), pid != ownPID else { continue }
            let bundle: String = Self.readString(id, kAudioProcessPropertyBundleID) ?? ""
            let input: UInt32 = Self.read(id, kAudioProcessPropertyIsRunningInput) ?? 0
            let output: UInt32 = Self.read(id, kAudioProcessPropertyIsRunningOutput) ?? 0
            let resolvedBundle = Self.canonicalBundle(bundle.isEmpty
                ? (NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid.\(pid)")
                : bundle)
            let rootPID = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == resolvedBundle }?.processIdentifier ?? pid
            next.append(AudioProcessInfo(
                objectID: id,
                pid: rootPID,
                bundleID: resolvedBundle,
                isRunningInput: input != 0,
                isRunningOutput: output != 0
            ))
        }
        // Chromium can put input and output in separate audio process objects. Combine
        // them by owning app before looking for a two-way call.
        let grouped = Dictionary(grouping: next, by: \.bundleID).values.compactMap { group -> AudioProcessInfo? in
            guard let first = group.first else { return nil }
            return AudioProcessInfo(objectID: first.objectID, pid: first.pid, bundleID: first.bundleID,
                                    isRunningInput: group.contains(where: \.isRunningInput),
                                    isRunningOutput: group.contains(where: \.isRunningOutput))
        }.sorted { $0.bundleID < $1.bundleID }
        if grouped != processes { processes = grouped }
    }

    private static func canonicalBundle(_ bundle: String) -> String {
        MeetingAppRegistry.apps.first {
            bundle == $0.bundleID || bundle.lowercased().hasPrefix($0.bundleID.lowercased() + ".")
        }?.bundleID ?? bundle
    }

    // MARK: - Listener

    private func installListener() {
        guard !listenerInstalled else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        listenerBlock = block
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.listAddress, .main, block
        )
        listenerInstalled = status == noErr
        if status != noErr { Log.audio.error("process list listener failed: \(status)") }
    }

    // MARK: - Property reads

    private static func processObjectIDs() -> [AudioObjectID] {
        var address = listAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, buffer.baseAddress!)
        }
        return status == noErr ? ids : []
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
