import Foundation
@testable import MarkdownEngine
import Testing

struct ParseEngineWorkerOwnershipTests {
    @Test(arguments: [false, true])
    func aPhysicalWorkerRetainsItsSlotUntilItReturns(cancelOwner: Bool) async throws {
        let probe = ParseWorkerProbe()
        defer { probe.releaseFirst() }
        let engine = ParseEngine(beforeRequest: { probe.request($0) }, beforeSynchronousParse: { probe.work($0) })
        let first = Task { try await engine.parse("# First", revision: 1) }
        try await waitUntil { probe.started(1) }
        let second = Task { try await engine.parse("# Second", revision: 2) }
        try await waitUntil { probe.requested(2) }
        if cancelOwner {
            first.cancel()
        }
        try await Task.sleep(for: .milliseconds(100))
        let overlapped = probe.started(2)
        probe.releaseFirst()
        if cancelOwner {
            do {
                _ = try await first.value
                Issue.record("Expected owner cancellation")
            } catch is CancellationError {}
        } else {
            #expect(try await first.value.revision == 1)
        }
        #expect(try await second.value.revision == 2)
        #expect(!overlapped, "A queued parse started while the prior physical worker was still held")
        #expect(probe.peak == 1)
        #expect(!probe.expired)
    }

    @Test func cancelingAQueuedRequestIsPromptAndDoesNotStartPhysicalWork() async throws {
        let probe = ParseWorkerProbe()
        defer { probe.releaseFirst() }
        let engine = ParseEngine(beforeRequest: { probe.request($0) }, beforeSynchronousParse: { probe.work($0) })
        let first = Task { try await engine.parse("# First", revision: 1) }
        try await waitUntil { probe.started(1) }
        let second = Task { try await engine.parse("# Canceled", revision: 2) }
        try await waitUntil { probe.requested(2) }
        let third = Task { try await engine.parse("# Third", revision: 3) }
        try await waitUntil { probe.requested(3) }
        second.cancel()
        let cancellation = Task {
            do {
                _ = try await second.value
                probe.completeCancellation(false)
            } catch is CancellationError {
                probe.completeCancellation(true)
            } catch {
                probe.completeCancellation(false)
            }
        }
        try await waitUntil { probe.cancellationFinished }
        #expect(probe.canceled)
        #expect(!probe.started(2))
        #expect(!probe.started(3))
        probe.releaseFirst()
        _ = try await first.value
        #expect(try await third.value.revision == 3)
        await cancellation.value
        #expect(probe.order == [1, 3])
        #expect(probe.peak == 1)
        #expect(!probe.expired)
    }

    private func waitUntil(_ condition: @escaping @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw ProbeTimeout() }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

private struct ProbeTimeout: Error {}

private final class ParseWorkerProbe: @unchecked Sendable {
    private let condition = NSCondition()
    private var requests: Set<Int> = []
    private var starts: [Int] = []
    private var active = 0
    private var maximum = 0
    private var released = false
    private var didExpire = false
    private var didFinishCancellation = false
    private var wasCanceled = false

    func request(_ revision: Int) {
        locked { requests.insert(revision) }
    }

    func requested(_ revision: Int) -> Bool {
        locked { requests.contains(revision) }
    }

    func started(_ revision: Int) -> Bool {
        locked { starts.contains(revision) }
    }

    var peak: Int {
        locked { maximum }
    }

    var order: [Int] {
        locked { starts }
    }

    var expired: Bool {
        locked { didExpire }
    }

    var cancellationFinished: Bool {
        locked { didFinishCancellation }
    }

    var canceled: Bool {
        locked { wasCanceled }
    }

    func completeCancellation(_ canceled: Bool) {
        locked { wasCanceled = canceled; didFinishCancellation = true }
    }

    func releaseFirst() {
        locked { released = true; condition.broadcast() }
    }

    func work(_ revision: Int) {
        condition.lock()
        starts.append(revision)
        active += 1
        maximum = max(maximum, active)
        let deadline = Date().addingTimeInterval(5)
        while revision == 1, !released {
            if !condition.wait(until: deadline) {
                didExpire = true; break
            }
        }
        active -= 1
        condition.unlock()
    }

    @discardableResult
    private func locked<T>(_ body: () -> T) -> T {
        condition.lock()
        defer { condition.unlock() }
        return body()
    }
}
