import Foundation
import Synchronization

struct PreparedReply: Sendable {
    enum Kind: String, Sendable { case rich, fallback, busy, failed }
    let kind: Kind
    let html: Data
}

/// Result permission is independent of the actual renderer's continued occupancy.
final class DeadlineGate: Sendable {
    private struct State {
        var waiting = false
        var result: PreparedReply?
        var continuation: CheckedContinuation<PreparedReply, Never>?
    }

    private let state = Mutex(State())

    func value() async -> PreparedReply {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> PreparedReply? in
                precondition(!state.waiting, "One actual consumer per request")
                state.waiting = true
                if let result = state.result {
                    return result
                }
                state.continuation = continuation
                return nil
            }
            if let ready {
                continuation.resume(returning: ready)
            }
        }
    }

    @discardableResult
    func select(_ result: PreparedReply, onSelection: @Sendable () -> Void = {}) -> Bool {
        let decision = state.withLock { state -> (Bool, CheckedContinuation<PreparedReply, Never>?) in
            guard state.result == nil else { return (false, nil) }
            state.result = result
            let continuation = state.continuation
            state.continuation = nil
            onSelection()
            return (true, continuation)
        }
        decision.1?.resume(returning: result)
        return decision.0
    }
}

final class RendererOccupancy: Sendable {
    private let occupied = Mutex(false)

    func acquire() -> Lease? {
        occupied.withLock { value in
            guard !value else { return nil }
            value = true
            return Lease(owner: self)
        }
    }

    private func release() {
        occupied.withLock { value in
            precondition(value)
            value = false
        }
    }

    final class Lease: Sendable {
        private let owner: RendererOccupancy
        private let released = Mutex(false)

        fileprivate init(owner: RendererOccupancy) {
            self.owner = owner
        }

        func releaseAfterActualWorkerReturn() {
            released.withLock { value in
                guard !value else { return }
                value = true
                owner.release()
            }
        }
    }
}
