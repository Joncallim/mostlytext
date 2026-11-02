import Dispatch
import Foundation

final class SavePublicationBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private var arrived = false
    private var didEnterWriterLane = false
    private var shouldWait = true
    private var shouldHoldSecond = false
    private let continuation = DispatchSemaphore(value: 0)
    private let secondContinuation = DispatchSemaphore(value: 0)
    private var arrivalContinuation: CheckedContinuation<Bool, Never>?
    private var secondSaveContinuation: CheckedContinuation<Bool, Never>?

    var hasArrived: Bool {
        lock.lock()
        defer { lock.unlock() }
        return arrived
    }

    func arriveAndWait() {
        lock.lock()
        arrived = true
        let waits = shouldWait
        shouldWait = false
        let arrivalContinuation = arrivalContinuation
        self.arrivalContinuation = nil
        lock.unlock()
        arrivalContinuation?.resume(returning: true)
        guard waits else { return }
        _ = continuation.wait(timeout: .now() + 3)
    }

    func allowPublication() {
        continuation.signal()
    }

    func waitForFirstPublication() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if arrived {
                lock.unlock()
                continuation.resume(returning: true)
            } else {
                arrivalContinuation = continuation
                lock.unlock()
            }
        }
    }

    func secondSaveEnteredWriterLane() {
        lock.lock()
        didEnterWriterLane = true
        let holdSecond = shouldHoldSecond
        let continuation = secondSaveContinuation
        secondSaveContinuation = nil
        lock.unlock()
        continuation?.resume(returning: true)
        if holdSecond {
            _ = secondContinuation.wait(timeout: .now() + 30)
        }
    }

    func holdSecondPublication() {
        lock.lock()
        shouldHoldSecond = true
        lock.unlock()
    }

    func allowSecondPublication() {
        secondContinuation.signal()
    }

    func waitForSecondSaveToEnterWriterLane() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didEnterWriterLane {
                lock.unlock()
                continuation.resume(returning: true)
            } else {
                secondSaveContinuation = continuation
                lock.unlock()
            }
        }
    }

    func cancelWaiters() {
        lock.lock()
        let arrival = arrivalContinuation
        let second = secondSaveContinuation
        arrivalContinuation = nil
        secondSaveContinuation = nil
        lock.unlock()
        arrival?.resume(returning: false)
        second?.resume(returning: false)
    }

    func cancelAndAllowPublication() {
        cancelWaiters()
        allowPublication()
        allowSecondPublication()
    }
}
