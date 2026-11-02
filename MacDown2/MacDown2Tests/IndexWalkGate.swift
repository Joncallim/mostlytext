import Foundation

/// The index walk deliberately occupies a worker. Its readiness waiter must
/// not block another Swift cooperative worker needed to start that walk.
final class IndexWalkGate: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)
    private let beforeWait: (@Sendable () -> Void)?

    init(beforeWait: (@Sendable () -> Void)? = nil) {
        self.beforeWait = beforeWait
    }

    func blockUntilReleased() {
        started.signal()
        releaseSignal.wait()
    }

    @MainActor func waitUntilBlocked(timeout: DispatchTime = .now() + 5) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                self.beforeWait?()
                continuation.resume(returning: self.started.wait(timeout: timeout) == .success)
            }
        }
    }

    func release() {
        releaseSignal.signal()
    }
}
