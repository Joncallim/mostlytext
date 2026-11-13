@testable import Highlighting
import SwiftTreeSitterLayer
import Testing

@MainActor
@Suite("Mounted Markdown physical parse ownership", .serialized)
struct MarkdownViewportParseQueueTests {
    @Test(.timeLimit(.minutes(2)))
    func cancelledActiveWorkRetainsItsSlotAndQueuedCancellationIsPrompt() async throws {
        let probe = HeldSnapshotParser()
        let registry = GrammarRegistry()
        let queue = MarkdownViewportParseQueue(capacity: 2) { source, registry in
            try await probe.parse(source, registry: registry)
        }
        let first = Task { try await queue.snapshot(source: "alpha", registry: registry) }
        let second = Task { try await queue.snapshot(source: "beta", registry: registry) }
        #expect(await eventually { await probe.startedCount == 2 })
        #expect(await queue.activeCountForTesting == 2)

        let cancelledWaiter = Task { try await queue.snapshot(source: "discard", registry: registry) }
        #expect(await eventually { await queue.queuedCountForTesting == 1 })
        cancelledWaiter.cancel()
        await #expect(throws: CancellationError.self) { try await cancelledWaiter.value }
        #expect(await queue.queuedCountForTesting == 0)
        #expect(await probe.startedCount == 2)

        let replacement = Task { try await queue.snapshot(source: "gamma", registry: registry) }
        #expect(await eventually { await queue.queuedCountForTesting == 1 })
        first.cancel()
        #expect(await queue.activeCountForTesting == 2)
        #expect(await probe.startedCount == 2)

        await probe.release("alpha")
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await eventually { await probe.startedCount == 3 })
        #expect(await probe.started == ["alpha", "beta", "gamma"])
        await probe.release("beta")
        await probe.release("gamma")
        _ = try await second.value
        _ = try await replacement.value
        #expect(await queue.activeCountForTesting == 0)
        #expect(await queue.queuedCountForTesting == 0)
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0 ..< 10000 {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

private actor HeldSnapshotParser {
    private(set) var started: [String] = []
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]

    var startedCount: Int {
        started.count
    }

    func parse(_ source: String, registry: GrammarRegistry) async throws -> LanguageLayerTreeSnapshot {
        started.append(source)
        await withCheckedContinuation { continuation in
            gates[source] = continuation
        }
        return try MarkdownSectionParser.snapshot(source: source, registry: registry)
    }

    func release(_ source: String) {
        gates.removeValue(forKey: source)?.resume()
    }
}
