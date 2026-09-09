import Foundation
import Synchronization

/// Each recognizer's sample clock begins at its first buffer. Align both streams to the
/// meeting clock even when system-audio consent delays the call stream by minutes.
public final class CaptureTimeline: Sendable {
    private struct State { var origin: Date?; var first: [AudioStreamSource: Date] = [:] }
    private let state = Mutex(State())
    public init() {}
    public func begin(at date: Date) { state.withLock { $0.origin = date; $0.first = [:] } }
    public func observe(_ source: AudioStreamSource, at date: Date = Date()) {
        state.withLock { if $0.first[source] == nil { $0.first[source] = date } }
    }
    public func offset(for source: AudioStreamSource) -> TimeInterval {
        state.withLock {
            guard let origin = $0.origin, let first = $0.first[source] else { return 0 }
            return max(0, first.timeIntervalSince(origin))
        }
    }
}
