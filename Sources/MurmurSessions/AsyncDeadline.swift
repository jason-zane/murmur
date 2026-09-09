import Foundation
import Synchronization

/// Unlike a task-group race, this returns at the deadline even when framework work ignores
/// cancellation. Late results cannot resume a continuation twice or overwrite new work.
public enum AsyncDeadline {
    public struct TimedOut: LocalizedError, Sendable {
        public var errorDescription: String? { "The on-device model took too long. Your notes are safe; try again." }
    }

    public static func run<Value: Sendable>(for duration: Duration,
        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let completion = Completion<Value>()
        let worker = Task {
            do { completion.resolve(.success(try await operation())) }
            catch { completion.resolve(.failure(error)) }
        }
        let timer = Task {
            do { try await Task.sleep(for: duration); completion.resolve(.failure(TimedOut())); worker.cancel() }
            catch {}
        }
        defer { timer.cancel(); worker.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { completion.install($0) }
        } onCancel: {
            completion.resolve(.failure(CancellationError()))
            worker.cancel()
        }
    }

    private final class Completion<Value: Sendable>: Sendable {
        private struct State {
            var result: Result<Value, Error>?
            var continuation: CheckedContinuation<Value, Error>?
        }
        private let state = Mutex(State())
        func install(_ continuation: CheckedContinuation<Value, Error>) {
            let result = state.withLock { value -> Result<Value, Error>? in
                if let result = value.result { return result }
                value.continuation = continuation
                return nil
            }
            if let result { continuation.resume(with: result) }
        }
        func resolve(_ result: Result<Value, Error>) {
            let continuation = state.withLock { value -> CheckedContinuation<Value, Error>? in
                guard value.result == nil else { return nil }
                value.result = result
                defer { value.continuation = nil }
                return value.continuation
            }
            continuation?.resume(with: result)
        }
    }
}
