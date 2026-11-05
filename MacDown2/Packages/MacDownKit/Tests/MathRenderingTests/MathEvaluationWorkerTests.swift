import Foundation
@testable import MathRendering
import Testing

/// An explicitly released computation ignores ambient cancellation. Tests observe
/// actual starts, never infer physical concurrency from a cancellation flag.
private actor MathWorkerGate {
    private var started: [UUID] = []
    private var releases: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var observers: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func suspend(_ id: UUID) async {
        await withCheckedContinuation { continuation in
            releases[id] = continuation
            started.append(id)
            for observer in observers.removeValue(forKey: id) ?? [] {
                observer.resume()
            }
        }
    }

    func waitForStart(_ id: UUID) async {
        guard !started.contains(id) else { return }
        await withCheckedContinuation { observers[id, default: []].append($0) }
    }

    func release(_ id: UUID) {
        releases.removeValue(forKey: id)?.resume()
    }

    func releaseAll() {
        let values = Array(releases.values)
        releases.removeAll()
        for continuation in values {
            continuation.resume()
        }
    }

    var starts: [UUID] {
        started
    }
}

@Suite(.timeLimit(.minutes(1)))
struct MathEvaluationWorkerTests {
    @Test func noncooperativeCancellationRetainsPhysicalSlotAndOnlyNewestPendingRequest() async throws {
        let first = try await MathEvaluationTests.request(generation: 1)
        let second = try await MathEvaluationTests.request(generation: 2)
        let third = try await MathEvaluationTests.request(generation: 3)
        let prepared = try first.evaluate()
        let gate = MathWorkerGate()
        let worker = MathEvaluationWorker { request in
            await gate.suspend(request.id)
            return prepared
        }
        defer { Task { await worker.shutdown(); await gate.releaseAll() } }
        let one = Task { await worker.submit(first) }
        await gate.waitForStart(first.id)
        let two = Task { await worker.submit(second) }
        guard case .superseded = await one.value else { Issue.record("First caller must be superseded"); return }
        let three = Task { await worker.submit(third) }
        guard case .superseded = await two.value else { Issue.record("Only newest pending request survives"); return }
        #expect(await gate.starts == [first.id])
        await gate.release(first.id)
        await gate.waitForStart(third.id)
        #expect(await gate.starts == [first.id, third.id])
        await gate.release(third.id)
        guard case .completed = await three.value else { Issue.record("Newest result should complete"); return }
        await worker.shutdown()
    }

    @Test func callerCancellationRemovesPendingWithoutStartingIt() async throws {
        let first = try await MathEvaluationTests.request(generation: 1)
        let second = try await MathEvaluationTests.request(generation: 2)
        let prepared = try first.evaluate()
        let gate = MathWorkerGate()
        let worker = MathEvaluationWorker { request in
            await gate.suspend(request.id)
            return prepared
        }
        defer { Task { await worker.shutdown(); await gate.releaseAll() } }
        let one = Task { await worker.submit(first) }
        await gate.waitForStart(first.id)
        let two = Task { await worker.submit(second) }
        guard case .superseded = await one.value else { Issue.record("Expected pending admission"); return }
        two.cancel()
        guard case .cancelled = await two.value else { Issue.record("Cancelled pending caller must resolve"); return }
        await gate.release(first.id)
        await worker.shutdown()
        #expect(await gate.starts == [first.id])
        guard case .cancelled = await worker.submit(second)
        else { Issue.record("Shutdown must reject new work"); return }
    }

    @Test func shutdownResolvesRunningAndPendingWithoutDroppingPhysicalOwnership() async throws {
        let first = try await MathEvaluationTests.request(generation: 1)
        let second = try await MathEvaluationTests.request(generation: 2)
        let prepared = try first.evaluate()
        let gate = MathWorkerGate()
        let worker = MathEvaluationWorker { request in
            await gate.suspend(request.id)
            return prepared
        }
        defer { Task { await worker.shutdown(); await gate.releaseAll() } }
        let one = Task { await worker.submit(first) }
        await gate.waitForStart(first.id)
        let two = Task { await worker.submit(second) }
        _ = await one.value
        await worker.shutdown()
        guard case .cancelled = await two.value else { Issue.record("Shutdown must resolve pending caller"); return }
        #expect(await gate.starts == [first.id])
        await gate.release(first.id)
    }

    @Test func failuresReleasePhysicalSlotForLaterRealPreparation() async throws {
        enum InjectedFailure: Error { case expected }
        let worker = MathEvaluationWorker { request in
            if request.generation == 1 {
                throw InjectedFailure.expected
            }
            return try request.evaluate()
        }
        let first = try await MathEvaluationTests.request(generation: 1)
        let second = try await MathEvaluationTests.request("$y$", generation: 2)
        guard case .failed = await worker.submit(first) else { Issue.record("Expected injected failure"); return }
        guard case let .completed(value) = await worker.submit(second)
        else { Issue.record("Worker must recover"); return }
        #expect(value.analysis.revision == 2)
        #expect(value.entries.first?.equation.rendererExpression == "y")
        await worker.shutdown()
    }

    @Test func shutdownResolvesAnActiveCallerBeforeNoncooperativeWorkReturns() async throws {
        let request = try await MathEvaluationTests.request()
        let prepared = try request.evaluate()
        let gate = MathWorkerGate()
        let worker = MathEvaluationWorker { request in
            await gate.suspend(request.id)
            return prepared
        }
        defer { Task { await worker.shutdown(); await gate.releaseAll() } }
        let task = Task { await worker.submit(request) }
        await gate.waitForStart(request.id)
        await worker.shutdown()
        guard case .cancelled = await task.value else { Issue.record("Active waiter must resolve at shutdown"); return }
        #expect(await gate.starts == [request.id])
        guard case .cancelled = await worker.submit(request) else { Issue.record("Shutdown is terminal"); return }
        await gate.release(request.id)
    }

    @Test func independentDocumentWorkerDoesNotWaitForAnotherDocumentsBlockedWork() async throws {
        let request = try await MathEvaluationTests.request()
        let prepared = try request.evaluate()
        let gate = MathWorkerGate()
        let blocked = MathEvaluationWorker { request in
            await gate.suspend(request.id)
            return prepared
        }
        defer { Task { await blocked.shutdown(); await gate.releaseAll() } }
        let first = Task { await blocked.submit(request) }
        await gate.waitForStart(request.id)
        let independent = MathEvaluationWorker()
        guard case .completed = await independent.submit(request)
        else { Issue.record("Independent document stalled"); return }
        await gate.release(request.id)
        guard case .completed = await first.value else { Issue.record("Released work should complete"); return }
        await blocked.shutdown()
        await independent.shutdown()
    }
}
