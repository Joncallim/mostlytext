import Foundation
import MarkdownEngine

/// An engine whose every `parse` call suspends until the test releases that
/// specific call, so overlapping parses are interleaved deterministically
/// (no sleeps, no polling for a momentary state).
actor GatedParseEngine: ParseExecuting {
    private var started = 0
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<Int> = []

    func parse(_ text: String, options: MarkdownParseOptions, revision: Int) async throws -> MarkdownDocument {
        started += 1
        let call = started
        let ready = startWaiters.filter { $0.count <= started }
        startWaiters.removeAll { $0.count <= started }
        for waiter in ready {
            waiter.continuation.resume()
        }
        if !released.contains(call) {
            await withCheckedContinuation { gates[call] = $0 }
        }
        return MarkdownDocument(
            body: text,
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: text),
            revision: revision,
            options: options
        )
    }

    func waitUntilStarted(_ count: Int) async {
        if started >= count {
            return
        }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func release(call: Int) {
        released.insert(call)
        gates.removeValue(forKey: call)?.resume()
    }
}
