import Foundation
@testable import Highlighting
import Testing

@MainActor
@Suite("Bounded Markdown cache retirement")
struct BoundedMarkdownCacheRetirementTests {
    @Test(.timeLimit(.minutes(1)))
    func releasesOnWorkerBeforeReopeningSlotsAndBoundsBurstMemory() async throws {
        let log = LockedRetirementLog()
        let hold = RetirementHold()
        let retirement = BoundedMarkdownCacheRetirement()
        retirement.workerHoldForTesting = { await hold.wait() }
        retirement.onSlotReleasedForTesting = { log.append("slot") }

        retirement.retireProbeForTesting(RetirementSpy("one", log: log))
        retirement.retireProbeForTesting(RetirementSpy("two", log: log))
        #expect(retirement.inFlightCount == 2)
        retirement.retireProbeForTesting(RetirementSpy("overflow", log: log))
        #expect(retirement.inFlightCount == 2)
        #expect(retirement.overflowCount == 1)
        #expect(log.snapshot == ["drop-overflow-main"],
                "Overflow must release synchronously instead of retaining a third cache")

        await hold.release()
        for _ in 0 ..< 1000 where retirement.inFlightCount != 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(retirement.inFlightCount == 0)
        let events = log.snapshot
        #expect(events.filter { $0 == "slot" }.count == 2)
        #expect(events.contains("drop-one-worker"))
        #expect(events.contains("drop-two-worker"))
        var workerDrops = 0
        var reopenedSlots = 0
        for event in events {
            if event == "drop-one-worker" || event == "drop-two-worker" {
                workerDrops += 1
            } else if event == "slot" {
                #expect(workerDrops > reopenedSlots,
                        "A slot reopened before its cache was destroyed: \(events)")
                reopenedSlots += 1
            }
        }
    }
}

private actor RetirementHold {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}

private final class LockedRetirementLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private final class RetirementSpy {
    private let name: String
    private let log: LockedRetirementLog

    init(_ name: String, log: LockedRetirementLog) {
        self.name = name
        self.log = log
    }

    deinit {
        log.append("drop-\(name)-\(Thread.isMainThread ? "main" : "worker")")
    }
}
