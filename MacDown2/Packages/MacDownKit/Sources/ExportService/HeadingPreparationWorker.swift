import Foundation
import MarkdownEngine

/// A document's physical worker slot survives cooperative cancellation until its
/// computation returns. At most the newest pending request is retained beside it.
public actor HeadingPreparationWorker {
    public enum Outcome: Sendable {
        case completed(HeadingAnchorPreparation)
        case superseded
        case cancelled
        case failed(any Error)
    }

    private struct Job: Sendable {
        let id: UUID
        let request: HeadingPreparationRequest
        var continuation: CheckedContinuation<Outcome, Never>?
    }

    private struct Running {
        var job: Job
        let task: Task<Void, Never>
    }

    private let prepare: @Sendable (HeadingPreparationRequest) async throws -> HeadingAnchorPreparation
    private var running: Running?
    private var pending: Job?
    private var isShutdown = false

    public init() {
        prepare = { try await $0.prepare() }
    }

    /// Injection is internal and used to prove physical bounds with work that
    /// intentionally ignores cancellation; the public path always prepares the real source-bound heading index.
    init(prepare: @escaping @Sendable (HeadingPreparationRequest) async throws -> HeadingAnchorPreparation) {
        self.prepare = prepare
    }

    public func submit(_ request: HeadingPreparationRequest) async -> Outcome {
        guard !isShutdown, !Task.isCancelled else { return .cancelled }
        let submissionID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let job = Job(id: submissionID, request: request, continuation: continuation)
                guard running != nil else {
                    start(job)
                    return
                }
                pending?.continuation?.resume(returning: .superseded)
                pending = job
                running?.job.continuation?.resume(returning: .superseded)
                running?.job.continuation = nil
                running?.task.cancel()
            }
        } onCancel: {
            Task { await self.cancel(submissionID) }
        }
    }

    public func shutdown() {
        isShutdown = true
        pending?.continuation?.resume(returning: .cancelled)
        pending = nil
        running?.job.continuation?.resume(returning: .cancelled)
        running?.job.continuation = nil
        running?.task.cancel()
    }

    private func cancel(_ id: UUID) {
        if pending?.id == id {
            pending?.continuation?.resume(returning: .cancelled)
            pending = nil
        }
        if running?.job.id == id {
            running?.job.continuation?.resume(returning: .cancelled)
            running?.job.continuation = nil
            running?.task.cancel()
        }
    }

    private func start(_ job: Job) {
        let compute = prepare
        let task = Task.detached { [self] in
            let outcome: Outcome
            do {
                let value = try await compute(job.request)
                try Task.checkCancellation()
                outcome = .completed(value)
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed(error)
            }
            await finish(id: job.id, outcome: outcome)
        }
        running = Running(job: job, task: task)
    }

    private func finish(id: UUID, outcome: Outcome) {
        guard running?.job.id == id else { return }
        running?.job.continuation?.resume(returning: outcome)
        running = nil
        if let next = pending {
            pending = nil
            start(next)
        }
    }
}
