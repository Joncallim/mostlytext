@testable import ExportService
import Foundation
import MarkdownEngine
import Testing

/// An explicitly released computation ignores ambient cancellation. Tests observe
/// actual starts, never infer physical concurrency from a cancellation flag.
private actor HeadingWorkerGate {
    private var started: [UInt] = []
    private var releases: [UInt: CheckedContinuation<Void, Never>] = [:]
    private var observers: [UInt: [CheckedContinuation<Void, Never>]] = [:]

    func suspend(_ id: UInt) async {
        await withCheckedContinuation { continuation in
            releases[id] = continuation
            started.append(id)
            for observer in observers.removeValue(forKey: id) ?? [] {
                observer.resume()
            }
        }
    }

    func waitForStart(_ id: UInt) async {
        guard !started.contains(id) else { return }
        await withCheckedContinuation { observers[id, default: []].append($0) }
    }

    func release(_ id: UInt) {
        releases.removeValue(forKey: id)?.resume()
    }

    func releaseAll() {
        let values = Array(releases.values)
        releases.removeAll()
        for continuation in values {
            continuation.resume()
        }
    }

    var starts: [UInt] {
        started
    }
}

@Suite(.timeLimit(.minutes(1)))
struct HeadingPreparationWorkerTests {
    @Test func noncooperativeCancellationRetainsPhysicalSlotAndOnlyNewestPendingRequest() async throws {
        let first = try await request(generation: 1)
        let second = try await request(generation: 2)
        let third = try await request(generation: 3)
        let prepared = try await first.prepare()
        let gate = HeadingWorkerGate()
        let worker = HeadingPreparationWorker { request in
            await gate.suspend(request.sourceGeneration)
            return prepared
        }
        defer { Task { await worker.shutdown(); await gate.releaseAll() } }
        let one = Task { await worker.submit(first) }
        await gate.waitForStart(first.sourceGeneration)
        let two = Task { await worker.submit(second) }
        guard case .superseded = await one.value else { Issue.record("First caller must be superseded"); return }
        let three = Task { await worker.submit(third) }
        guard case .superseded = await two.value else { Issue.record("Only newest pending request survives"); return }
        #expect(await gate.starts == [first.sourceGeneration])
        await gate.release(first.sourceGeneration)
        await gate.waitForStart(third.sourceGeneration)
        #expect(await gate.starts == [first.sourceGeneration, third.sourceGeneration])
        await gate.release(third.sourceGeneration)
        guard case .completed = await three.value else { Issue.record("Newest result should complete"); return }
        await worker.shutdown()
    }

    @Test func callerCancellationRemovesPendingWithoutStartingIt() async throws {
        let first = try await request(generation: 1)
        let second = try await request(generation: 2)
        let prepared = try await first.prepare()
        let gate = HeadingWorkerGate()
        let worker = HeadingPreparationWorker { request in
            await gate.suspend(request.sourceGeneration)
            return prepared
        }
        defer { Task { await worker.shutdown(); await gate.releaseAll() } }
        let one = Task { await worker.submit(first) }
        await gate.waitForStart(first.sourceGeneration)
        let two = Task { await worker.submit(second) }
        guard case .superseded = await one.value else { Issue.record("Expected pending admission"); return }
        two.cancel()
        guard case .cancelled = await two.value else { Issue.record("Cancelled pending caller must resolve"); return }
        await gate.release(first.sourceGeneration)
        await worker.shutdown()
        #expect(await gate.starts == [first.sourceGeneration])
        guard case .cancelled = await worker.submit(second)
        else { Issue.record("Shutdown must reject new work"); return }
    }

    @Test func shutdownResolvesRunningAndPendingWithoutDroppingPhysicalOwnership() async throws {
        let first = try await request(generation: 1)
        let second = try await request(generation: 2)
        let prepared = try await first.prepare()
        let gate = HeadingWorkerGate()
        let worker = HeadingPreparationWorker { request in
            await gate.suspend(request.sourceGeneration)
            return prepared
        }
        defer { Task { await worker.shutdown(); await gate.releaseAll() } }
        let one = Task { await worker.submit(first) }
        await gate.waitForStart(first.sourceGeneration)
        let two = Task { await worker.submit(second) }
        _ = await one.value
        await worker.shutdown()
        guard case .cancelled = await two.value else { Issue.record("Shutdown must resolve pending caller"); return }
        #expect(await gate.starts == [first.sourceGeneration])
        await gate.release(first.sourceGeneration)
    }

    @Test func failuresReleasePhysicalSlotForLaterRealPreparation() async throws {
        enum InjectedFailure: Error { case expected }
        let worker = HeadingPreparationWorker { request in
            if request.sourceGeneration == 1 {
                throw InjectedFailure.expected
            }
            return try await request.prepare()
        }
        let first = try await request(generation: 1)
        let second = try await request("# Y\n", generation: 2)
        guard case .failed = await worker.submit(first) else { Issue.record("Expected injected failure"); return }
        guard case let .completed(value) = await worker.submit(second)
        else { Issue.record("Worker must recover"); return }
        #expect(value.index.identity.parseRevision == 2)
        #expect(value.index.headings.first?.title == "Y")
        await worker.shutdown()
    }

    @Test func shutdownResolvesAnActiveCallerBeforeNoncooperativeWorkReturns() async throws {
        let request = try await request()
        let prepared = try await request.prepare()
        let gate = HeadingWorkerGate()
        let worker = HeadingPreparationWorker { request in
            await gate.suspend(request.sourceGeneration)
            return prepared
        }
        defer { Task { await worker.shutdown(); await gate.releaseAll() } }
        let task = Task { await worker.submit(request) }
        await gate.waitForStart(request.sourceGeneration)
        await worker.shutdown()
        guard case .cancelled = await task.value else { Issue.record("Active waiter must resolve at shutdown"); return }
        #expect(await gate.starts == [request.sourceGeneration])
        guard case .cancelled = await worker.submit(request) else { Issue.record("Shutdown is terminal"); return }
        await gate.release(request.sourceGeneration)
    }

    @Test func independentDocumentWorkerDoesNotWaitForAnotherDocumentsBlockedWork() async throws {
        let request = try await request()
        let prepared = try await request.prepare()
        let gate = HeadingWorkerGate()
        let blocked = HeadingPreparationWorker { request in
            await gate.suspend(request.sourceGeneration)
            return prepared
        }
        defer { Task { await blocked.shutdown(); await gate.releaseAll() } }
        let first = Task { await blocked.submit(request) }
        await gate.waitForStart(request.sourceGeneration)
        let independent = HeadingPreparationWorker()
        guard case .completed = await independent.submit(request)
        else { Issue.record("Independent document stalled"); return }
        await gate.release(request.sourceGeneration)
        guard case .completed = await first.value else { Issue.record("Released work should complete"); return }
        await blocked.shutdown()
        await independent.shutdown()
    }

    private func request(_ source: String = "# Target\n",
                         generation: UInt = 1) async throws -> HeadingPreparationRequest {
        let parsed = try await ParseEngine().parse(source, revision: Int(generation))
        return HeadingPreparationRequest(
            document: parsed, sourceText: source, documentID: "own", recoveryEpoch: UUID(), sourceGeneration: generation
        )
    }
}
