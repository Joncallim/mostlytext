@testable import FileCore
import Foundation
import Testing

@Suite("Document file monitor parent recovery")
struct DocumentFileMonitorRecoveryTests {
    @Test func replacementWatcherProbesAReappearedFileWithoutAnotherEvent() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/reappearance-without-event.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let replacement = snapshot("replacement", at: fileURL)
        // The new watcher has no event for the already-reappeared file. Its
        // installation probe must nevertheless publish the replacement.
        let prober = ScriptedProber([
            .available(initial),
            .missing(fileURL),
            .missing(fileURL),
            .available(replacement),
        ])
        let recorder = MonitorRecoveryRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }

        watcher.signal(.parentVanished)

        await waitUntil { recorder.count == 3 }
        #expect(recorder.values == [.available(initial), .missing(fileURL), .available(replacement)])
        #expect(await prober.callCount == 4)
    }

    /// Both signals must land while the debounce is still pending. The debounce
    /// is therefore gated rather than a bare `Task.yield()`: with a yield, the
    /// `.parentVanished` debounce task can start probing before `.changed` is
    /// delivered (each signal reaches the actor through its own unstructured
    /// task), and that superseded probe consumes one of the scripted answers.
    /// See `changedEventDuringAnInFlightParentProbeKeepsTheRecoveryLatch` for
    /// that interleaving.
    @Test func parentVanishedLatchSurvivesAChangedEventDuringDebounce() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/parent-latch.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let recovered = snapshot("recovered", at: fileURL)
        let prober = ScriptedProber([
            .available(initial), .missing(fileURL), .missing(fileURL), .available(recovered),
        ])
        let recorder = MonitorRecoveryRecorder()
        let sleeper = GateSleeper()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: watcher,
            prober: prober,
            sleeper: { _ in await sleeper.sleep() }
        )
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }

        watcher.signal(.parentVanished)
        watcher.signal(.changed)
        // Two parked debounce tasks means both signals reached the monitor
        // before either could probe; the earlier one is already cancelled.
        await waitUntil { await sleeper.waiterCount == 2 }
        await sleeper.resumeAll()
        // The surviving probe saw `.missing` and parks on the confirmation wait.
        await waitUntil { await sleeper.waiterCount == 1 }
        await sleeper.resumeAll()

        await waitUntil { recorder.values.last == .available(recovered) }
        #expect(recorder.values == [.available(initial), .missing(fileURL), .available(recovered)])
        #expect(watcher.watchedDirectories.count == 2)
        #expect(await prober.callCount == 4)
    }

    /// The interleaving that failed on CI: the `.parentVanished` debounce has
    /// already started its probe when `.changed` arrives. The in-flight probe
    /// is superseded and its answer discarded, yet the latch still reinstalls
    /// the parent watcher, and the reinstall probe is what gets published.
    /// This costs one extra probe compared with the coalesced path above.
    @Test func changedEventDuringAnInFlightParentProbeKeepsTheRecoveryLatch() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/parent-latch-in-flight.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let superseded = snapshot("superseded", at: fileURL)
        let recovered = snapshot("recovered", at: fileURL)
        let prober = DeferredProber(initial: initial)
        let recorder = MonitorRecoveryRecorder()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: watcher,
            prober: prober,
            sleeper: { _ in await Task.yield() }
        )
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }

        watcher.signal(.parentVanished)
        await waitUntil { await prober.waiterCount == 1 }
        watcher.signal(.changed)
        await waitUntil { await monitor.currentRequestGeneration() == 3 }

        await prober.resume(superseded, at: 0)
        await waitUntil { await prober.waiterCount == 2 }
        await prober.resume(.missing(fileURL), at: 1)
        await waitUntil { await prober.waiterCount == 3 }
        await prober.resume(.missing(fileURL), at: 2)
        await waitUntil { await prober.waiterCount == 4 }
        #expect(watcher.watchedDirectories.count == 2)
        await prober.resume(recovered, at: 3)

        await waitUntil { recorder.values.last == .available(recovered) }
        #expect(recorder.values == [.available(initial), .missing(fileURL), .available(recovered)])
        #expect(await prober.callCount == 5)
    }

    @Test func parentVanishedReinstallsTheDirectoryWatcherAfterTheProbe() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/recreated-parent.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let afterRecreate = snapshot("after", at: fileURL)
        let prober = ScriptedProber([
            .available(initial),
            .available(afterRecreate),
            .available(afterRecreate),
        ])
        let recorder = MonitorRecoveryRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }

        watcher.signal(.parentVanished)

        await waitUntil { recorder.count == 3 }
        await waitUntil { watcher.watchedDirectories.count == 2 }
        #expect(watcher.cancelCount == 1)
    }

    @Test func parentRecoveryRetriesBeyondTheInitialQuarterSecondWindow() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/late-parent.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let recovered = snapshot("recovered", at: fileURL)
        let prober = ScriptedProber([.available(initial), .available(recovered)])
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { _ in }

        watcher.failNextWatchAttempts(2)
        watcher.signal(.parentVanished)

        await waitUntil { watcher.watchedDirectories.count == 2 }
        #expect(watcher.failedWatchCount == 2)
    }

    @Test func exhaustedParentRecoveryCanBeExplicitlyRetriedOnActivation() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/retry-after-backoff.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let recovered = snapshot("recovered", at: fileURL)
        let prober = ScriptedProber([.available(initial), .available(recovered)])
        let health = HealthRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(
            to: fileURL,
            priorFileObjectID: nil,
            onObservation: { _ in },
            onHealthChange: { value in
                health.append(value)
            }
        )

        watcher.failNextWatchAttempts(4)
        watcher.signal(.parentVanished)
        await waitUntil { watcher.failedWatchCount == 4 }
        await waitUntil { health.contains(.failed) }

        try await monitor.retryWatching()
        await waitUntil { health.last == .healthy }

        #expect(watcher.watchedDirectories.count == 2)
        #expect(await prober.callCount == 3)
        #expect(health.last == .healthy)
    }
}

/// A lock-based, synchronously-appending recorder -- matching
/// `DocumentFileMonitorTests.swift`'s own `HealthRecorder` -- not an actor.
/// `DocumentFileMonitor.emit(_:generation:sequence:)` calls `onObservation`
/// synchronously from within its own actor-serialized execution, so the
/// callback closures below can (and must) append synchronously too. An
/// earlier `actor`-based version instead wrapped every append in
/// `Task { await recorder.append(observation) }`, which independently
/// schedules a new unstructured task per observation; nothing guarantees
/// those tasks reach the recorder's actor executor in the same order they
/// were created under scheduler contention (e.g. the full package suite's
/// ~1,700 other tests all competing for the same global executor), so the
/// recorded `values` could land out of order even though `waitUntil`'s own
/// count-based wait had already succeeded. This was independently
/// documented (`planning/issue-57-findings.md`, predating #150 by over a
/// month) and only partially mitigated by #150's own unrelated timeout
/// widening (2s -> 10s) here, which raises the odds of the race resolving
/// in time but does not eliminate it. Appending synchronously via a lock
/// removes the extra scheduling hop -- and therefore the race -- entirely.
final class MonitorRecoveryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [DocumentFileObservation] = []

    var values: [DocumentFileObservation] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValues.count
    }

    func append(_ observation: DocumentFileObservation) {
        lock.lock()
        storedValues.append(observation)
        lock.unlock()
    }
}
