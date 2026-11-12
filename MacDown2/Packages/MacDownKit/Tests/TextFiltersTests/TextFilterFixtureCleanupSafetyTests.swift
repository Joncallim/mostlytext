import Darwin
import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter fixture cleanup safety")
struct TextFilterFixtureCleanupSafetyTests {
    private enum FixtureFailure: Error {
        case expected
    }

    private actor CleanupProbe {
        private(set) var cleanupJoinStartCount = 0
        private(set) var cleanupCallerFinishedCount = 0
        private(set) var taskFinished = false
        private var releaseRequested = false
        private var joinWaiters: [CheckedContinuation<Void, Never>] = []

        func holdCleanupJoin() async {
            cleanupJoinStartCount += 1
            await withCheckedContinuation { continuation in
                if releaseRequested {
                    continuation.resume()
                } else {
                    joinWaiters.append(continuation)
                }
            }
        }

        func releaseCleanupJoin() {
            releaseRequested = true
            let waiters = joinWaiters
            joinWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }

        func recordCleanupCallerFinished() {
            cleanupCallerFinishedCount += 1
        }

        func recordTaskFinished() {
            taskFinished = true
        }
    }

    @Test func concurrentCleanupCallersShareTheSameJoinTask() async throws {
        let probe = CleanupProbe()
        let owner = TextFilterFixtures.TaskOwner()
        try await owner.registerCleanup(
            cancel: {},
            join: {
                await probe.holdCleanupJoin()
                return .completed(nil)
            }
        )

        let first = Task {
            let joinTask = await owner.cancelAllAndCreateJoinTask()
            _ = await joinTask.value
            await probe.recordCleanupCallerFinished()
        }
        let second = Task {
            let joinTask = await owner.cancelAllAndCreateJoinTask()
            _ = await joinTask.value
            await probe.recordCleanupCallerFinished()
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if await probe.cleanupJoinStartCount > 0 {
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await probe.cleanupJoinStartCount == 1)
        #expect(await probe.cleanupCallerFinishedCount == 0)
        await probe.releaseCleanupJoin()

        _ = await first.value
        _ = await second.value
        #expect(await probe.cleanupJoinStartCount == 1)
        #expect(await probe.cleanupCallerFinishedCount == 2)
    }

    @Test func nonCooperativeCleanupUsesAWatchdogAndPreservesDirectoryWhenUnresolved() async throws {
        let probe = CleanupProbe()
        var observedDirectory: URL?
        var worker: Task<Void, any Error>?

        do {
            try await TextFilterFixtures
                .withOwnedTemporaryDirectory(cleanupTimeout: .milliseconds(25)) { directory, owner in
                    observedDirectory = directory
                    worker = try await owner.start {
                        usleep(200_000)
                        await probe.recordTaskFinished()
                    }
                    throw FixtureFailure.expected
                }
            Issue.record("expected fixture cleanup to exceed its watchdog")
        } catch let error as TextFilterFixtures.FixtureCleanupError {
            if case let .cleanupTimedOut(primary, timeout) = error {
                #expect(primary?.contains("expected") == true)
                #expect(timeout == .milliseconds(25))
            } else {
                Issue.record("unexpected fixture cleanup error: \(error)")
            }
        }

        if let directory = observedDirectory {
            #expect(FileManager.default.fileExists(atPath: directory.path))
        } else {
            Issue.record("noncooperative fixture directory was not recorded")
        }
        #expect(await !probe.taskFinished)
        if let worker {
            _ = try? await worker.value
        } else {
            Issue.record("owned worker handle was not captured")
        }
        #expect(await probe.taskFinished)
        if let directory = observedDirectory {
            #expect(FileManager.default.fileExists(atPath: directory.path))
            try FileManager.default.removeItem(at: directory)
        }
    }

    @Test func unresolvedCleanupPreservesOrdinaryCleanupFailures() async throws {
        var observedDirectory: URL?
        do {
            try await TextFilterFixtures.withOwnedTemporaryDirectory { directory, owner in
                observedDirectory = directory
                try await owner.registerCleanup(
                    cancel: {},
                    join: { .completed("important cleanup failure") }
                )
                try await owner.registerCleanup(
                    cancel: {},
                    join: { .unresolved("worker still running") }
                )
            }
            Issue.record("expected unresolved cleanup")
        } catch let error as TextFilterFixtures.FixtureCleanupError {
            if case let .cleanupUnresolved(_, reasons) = error {
                #expect(reasons.contains("worker still running"))
                #expect(reasons.contains("cleanup failure: important cleanup failure"))
            } else {
                Issue.record("unexpected fixture cleanup error: \(error)")
            }
        }

        if let observedDirectory {
            try? FileManager.default.removeItem(at: observedDirectory)
        }
    }

    private actor CancellationAwareJoinProbe {
        private var forcedRelease = false
        private var observedCancellation = false
        private var finished = false

        func join() async -> FixtureCleanupJoinResult {
            // This executes in the aggregate's actual child task, so its
            // cancellation state is the contract under test.
            while !Task.isCancelled, !forcedRelease {
                try? await Task.sleep(for: .milliseconds(5))
            }
            observedCancellation = Task.isCancelled
            finished = true
            return .unresolved(observedCancellation ? "aggregate join was cancelled" : "test released the join")
        }

        func waitForCancellation() async -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !finished, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(5))
            }
            return finished && observedCancellation
        }

        func releaseForTeardown() {
            forcedRelease = true
        }
    }

    @Test func cleanupTimeoutCancelsTheInnerAggregateJoinAndItsObserverCanFinish() async {
        let probe = CancellationAwareJoinProbe()
        var observedDirectory: URL?
        var observedOwner: TextFilterFixtures.TaskOwner?

        do {
            try await TextFilterFixtures
                .withOwnedTemporaryDirectory(cleanupTimeout: .milliseconds(25)) { directory, owner in
                    observedDirectory = directory
                    observedOwner = owner
                    try await owner.registerCleanup(
                        cancel: {},
                        join: { await probe.join() }
                    )
                }
            Issue.record("expected cleanup watchdog to cancel the aggregate join")
        } catch let error as TextFilterFixtures.FixtureCleanupError {
            if case .cleanupTimedOut = error {} else {
                Issue.record("unexpected fixture cleanup error: \(error)")
            }
        } catch {
            Issue.record("unexpected fixture failure: \(error)")
        }

        #expect(await probe.waitForCancellation(), "timeout must cancel the actual aggregate child join")
        // Even a missing-cancellation regression must leave no suspended work.
        // Observe cancellation first so this fallback cannot satisfy the test.
        await probe.releaseForTeardown()
        if let observedOwner {
            let aggregate = await observedOwner.cancelAllAndCreateJoinTask()
            _ = await aggregate.value
        } else {
            Issue.record("fixture owner was not captured")
        }

        if let directory = observedDirectory {
            #expect(FileManager.default.fileExists(atPath: directory.path))
            try? FileManager.default.removeItem(at: directory)
        } else {
            Issue.record("canceled-join fixture directory was not recorded")
        }
    }
}
