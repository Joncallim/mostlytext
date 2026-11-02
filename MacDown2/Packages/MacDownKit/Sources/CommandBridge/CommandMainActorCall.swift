import Foundation
import Synchronization

/// Only dedicated transport threads may block here. A late callback checks
/// its ticket before touching the app, and never executes after timeout/stop.
enum CommandMainActorCall {
    private struct State { var active = true; var result: Result<Void, any Error>? }
    static func perform(until deadline: ContinuousClock.Instant, isCancelled: @escaping @Sendable () -> Bool,
                        operation: @escaping @MainActor @Sendable () throws -> Void) throws {
        let state = Mutex(State())
        Task { @MainActor in
            // No await between owning this ticket and the synchronous submit.
            let claimed = state.withLock { value in
                guard value.active, !isCancelled(), ContinuousClock.now < deadline else { return false }
                value.active = false
                return true
            }
            guard claimed else { return }
            let result = Result { try operation() }
            state.withLock { $0.result = result }
        }
        defer { state.withLock { $0.active = false } }
        while true {
            if let result = state.withLock({ $0.result }) {
                return try result.get()
            }
            if isCancelled() {
                throw CommandSocketError.cancelled
            }
            guard ContinuousClock.now < deadline else { throw CommandSocketError.timedOut }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
}
