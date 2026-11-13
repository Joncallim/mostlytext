import Foundation
import SwiftTreeSitterLayer

/// Bounds physical Markdown tree-sitter parses across mounted editors.
/// Cancelling a caller cannot interrupt the synchronous C parser, so an
/// active request retains its slot until that parser actually returns.
actor MarkdownViewportParseQueue {
    typealias SnapshotParser = @Sendable (String, GrammarRegistry) async throws -> LanguageLayerTreeSnapshot

    static let shared = MarkdownViewportParseQueue(capacity: 2)

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let capacity: Int
    private let parser: SnapshotParser
    private var activeCount = 0
    private var waiters: [Waiter] = []

    init(capacity: Int, parser: @escaping SnapshotParser = { source, registry in
        try await Task.detached(priority: .utility) {
            try MarkdownSectionParser.snapshot(source: source, registry: registry)
        }.value
    }) {
        self.capacity = max(1, capacity)
        self.parser = parser
    }

    func snapshot(source: String, registry: GrammarRegistry) async throws -> LanguageLayerTreeSnapshot {
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await acquire(requestID)
            defer { release() }
            try Task.checkCancellation()
            let result = try await parser(source, registry)
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { await self.cancelQueued(requestID) }
        }
    }

    var activeCountForTesting: Int {
        activeCount
    }

    var queuedCountForTesting: Int {
        waiters.count
    }

    private func acquire(_ id: UUID) async throws {
        try Task.checkCancellation()
        if activeCount < capacity {
            activeCount += 1
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(Waiter(id: id, continuation: continuation))
        }
    }

    private func release() {
        if waiters.isEmpty {
            activeCount -= 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelQueued(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
