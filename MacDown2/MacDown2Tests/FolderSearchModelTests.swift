import FileCore
import Foundation
@testable import MacDown2
import Testing
import TextSearch

/// EPIC-22 §6.16, Slice 7b — `FolderSearchModel`'s own pure query/results
/// logic, mirroring `QuickOpenModelTests`' own separation of model tests
/// from panel/view presentation and its `waitUntil`/gate-based approach to
/// testing actor-backed async work deterministically rather than via
/// timing.
@Suite("FolderSearchModel")
@MainActor
struct FolderSearchModelTests {
    @Test func timedOutSearchKeepsStreamedRowsButCannotAuthorizeReplace() async {
        let streamed = FolderSearchMatch(
            relativePath: "a.txt", matches: [SearchMatch(range: NSRange(location: 0, length: 1))],
            revision: .placeholder
        )
        let model = FolderSearchModel(performSearch: { _, _, onMatch in
            await onMatch(streamed)
            return .timedOut(filesSearched: 1, filesSkipped: 1, matchCount: 1)
        })
        model.setRoot(URL(fileURLWithPath: "/tmp/folder-search-timeout"))
        model.query = "needle"
        await waitUntil { model.outcome != nil }

        #expect(model.results == [streamed])
        #expect(model.outcome == .timedOut(filesSearched: 1, filesSkipped: 1, matchCount: 1))
        #expect(model.unsearchedFileCount == 1)
        #expect(!model.canReplace)
        model.requestReplace()
        #expect(!model.isConfirmingReplace)
    }

    private final class TempTree {
        let root: URL

        init(_ files: [String: String]) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for (relativePath, text) in files {
                let url = root.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test func endToEndSearchFindsMatchesAcrossFiles() async throws {
        let tree = try TempTree(["a.txt": "hello world", "b.txt": "nothing here", "c.txt": "hello again"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = FolderSearchModel(index: index, debounce: .zero)

        model.setRoot(tree.root)
        model.query = "hello"
        await waitUntil { model.outcome != nil }

        #expect(Set(model.results.map(\.relativePath)) == ["a.txt", "c.txt"])
        #expect(model.outcome == .completed(filesSearched: 3, filesSkipped: 0, matchCount: 2))
        #expect(!model.isSearching)
    }

    @Test func oldRenderedRowCannotBorrowNewRootsSearchIdentity() async throws {
        let first = try TempTree(["same.md": "needle"])
        let second = try TempTree(["same.md": "needle"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: first.root)
        let model = FolderSearchModel(index: index, debounce: .zero)
        model.setRoot(first.root)
        model.query = "needle"
        await waitUntil { model.presentedResults.count == 1 }
        let oldRow = try #require(model.presentedResults.first)
        #expect(model.isCurrentResult(oldRow))

        model.setRoot(nil)
        #expect(!model.isCurrentResult(oldRow))
        await index.rebuild(root: second.root)
        model.setRoot(second.root)
        await waitUntil { model.presentedResults.count == 1 }
        let newRow = try #require(model.presentedResults.first)

        #expect(oldRow.match.relativePath == newRow.match.relativePath)
        #expect(oldRow.id != newRow.id)
        #expect(!model.isCurrentResult(oldRow))
        #expect(model.isCurrentResult(newRow))
    }

    @Test func emptyQueryClearsResultsWithoutSearching() async throws {
        let tree = try TempTree(["a.txt": "hello world"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = FolderSearchModel(index: index, debounce: .zero)
        model.setRoot(tree.root)

        model.query = "hello"
        await waitUntil { !model.results.isEmpty }

        model.query = ""

        #expect(model.results.isEmpty)
        #expect(model.outcome == nil)
        #expect(!model.isSearching)
    }

    @Test func rapidQueryEditsAreDebouncedIntoASingleRealSearch() async {
        // Coalesces rapid keystrokes into one real search, mirroring
        // `MarkdownParseSession.textDidChange`'s own acceptance test shape
        // -- but tests this end-to-end through `scheduleSearch`'s own
        // cancellation of a PENDING (still-debouncing) task, not just the
        // debounce mechanism in isolation.
        let callCount = CallCounter()
        let model = FolderSearchModel(performSearch: { _, _, _ in
            await callCount.increment()
            return .completed(filesSearched: 0, filesSkipped: 0, matchCount: 0)
        }, debounce: .milliseconds(20))
        model.setRoot(URL(fileURLWithPath: "/tmp/folder-search-debounce-test"))

        model.query = "a"
        model.query = "ab"
        model.query = "abc"

        // Settle on the search's own completion, not a fixed sleep: earlier
        // pending tasks are cancelled inside their debounce sleep and can
        // never reach `performSearch`, so once the last one finishes the
        // count is final.
        await waitUntil { model.outcome != nil }

        #expect(
            await callCount.value == 1,
            "rapid consecutive query edits must coalesce into a single real search, not one per keystroke"
        )
    }

    @Test func settingARootWithAnAlreadyTypedQueryRunsASearchAgainstIt() async throws {
        let tree = try TempTree(["a.txt": "needle"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = FolderSearchModel(index: index, debounce: .zero)

        // Query typed before any root is set: nothing to search against yet.
        model.query = "needle"
        #expect(!model.isSearching)
        #expect(model.results.isEmpty)

        model.setRoot(tree.root)
        await waitUntil { model.results.count == 1 }

        #expect(model.results.first?.relativePath == "a.txt")
    }

    @Test func aNewerQueryDiscardsALateArrivingStaleQuerysResult() async {
        // Forces the exact completion-order inversion `scheduleSearch`'s
        // generation counter exists to handle -- a NEWER query's outcome
        // committing before an OLDER, now-superseded query's own late
        // result streams in -- via a controllable `performSearch` seam,
        // the same shape as `QuickOpenModelTests.lateArrivingStaleQueryResultIsDiscarded`.
        let gate = SearchGate()
        let root = URL(fileURLWithPath: "/tmp/folder-search-model-tests")
        let staleMatch = FolderSearchMatch(
            relativePath: "stale.txt",
            matches: [SearchMatch(range: NSRange(location: 0, length: 1))],
            revision: .placeholder
        )
        let freshMatch = FolderSearchMatch(
            relativePath: "fresh.txt",
            matches: [SearchMatch(range: NSRange(location: 0, length: 1))],
            revision: .placeholder
        )
        let model = FolderSearchModel(performSearch: { _, query, onMatch in
            await gate.hold(query, onMatch: onMatch)
        })
        model.setRoot(root)

        model.query = "app" // generation 1 -- held, will stream staleMatch late
        model.query = "ban" // generation 2 -- held, will stream freshMatch first
        await gate.waitUntilPending("app")
        await gate.waitUntilPending("ban")

        // Resolve the NEWER query first -- exactly the inversion a real
        // single-actor search could never produce on its own.
        await gate.emit("ban", match: freshMatch)
        await gate.release("ban", with: .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        await waitUntil { model.results == [freshMatch] }

        // Now let the OLDER, already-superseded query stream and finish
        // LATE. A broken (or deleted) generation guard would let this
        // append onto the newer, already-committed results.
        await gate.emit("app", match: staleMatch)
        await gate.release("app", with: .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        await Task.yield()

        #expect(
            model.results == [freshMatch],
            "a late-arriving stale query's result must not be appended after a newer query committed"
        )
    }

    @Test func clearingTheRootCancelsTheInFlightSearchTaskRatherThanJustDiscardingItsResult() async {
        let gate = PauseGate()
        let observedCancellation = ObservedBool()
        let model = FolderSearchModel(performSearch: { _, _, _ in
            await gate.waitUntilReleased()
            await observedCancellation.set(Task.isCancelled)
            return .completed(filesSearched: 0, filesSkipped: 0, matchCount: 0)
        })

        model.setRoot(URL(fileURLWithPath: "/tmp/old-root"))
        model.query = "needle"
        await gate.waitUntilPaused()

        // Clearing the root (rather than setting a different one) is
        // deliberate: `scheduleSearch` only re-runs against a non-`nil`
        // root, so this isolates "was the OLD task actually cancelled"
        // from "did a second search also get started", which a
        // root-to-root change would conflate.
        model.setRoot(nil)
        await gate.release()
        await observedCancellation.waitForSet()

        #expect(
            await observedCancellation.value,
            "changing the root must actually cancel the in-flight search task, not just discard its eventual result"
        )
        #expect(model.results.isEmpty)
        #expect(!model.isSearching)
    }
}

private extension FileRevision {
    /// A stand-in revision for tests that only need a `FolderSearchMatch`
    /// to exist, not to be checked against a real on-disk file.
    static var placeholder: FileRevision {
        FileRevision(
            url: URL(fileURLWithPath: "/dev/null"),
            modificationDate: .distantPast,
            fileSize: 0,
            fileObjectID: nil,
            sha256: ""
        )
    }
}

/// A controllable stand-in for `WorkspaceSearchEngine.search`: each
/// distinct query string is held (via a real continuation, not a fixed
/// delay) until the test explicitly emits matches and releases it with a
/// chosen outcome, letting a test force any completion/streaming order it
/// wants — mirrors `QuickOpenModelTests`' own `QueryGate`, extended for a
/// streaming `onMatch` callback rather than a single return value.
private actor SearchGate {
    private var pending: [String: CheckedContinuation<FolderSearchOutcome, Never>] = [:]
    private var onMatchByQuery: [String: @Sendable (FolderSearchMatch) async -> Void] = [:]

    func hold(_ query: String,
              onMatch: @escaping @Sendable (FolderSearchMatch) async -> Void) async -> FolderSearchOutcome {
        onMatchByQuery[query] = onMatch
        return await withCheckedContinuation { pending[query] = $0 }
    }

    func emit(_ query: String, match: FolderSearchMatch) async {
        await onMatchByQuery[query]?(match)
    }

    func release(_ query: String, with outcome: FolderSearchOutcome) {
        pending.removeValue(forKey: query)?.resume(returning: outcome)
    }

    func waitUntilPending(_ query: String, timeout: Duration = .seconds(5)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if pending[query] != nil {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for query '\(query)' to become pending")
    }
}

/// Blocks the model's own `performSearch` call at a known pause point
/// until the test explicitly releases it — mirrors
/// `WorkspaceSearchEngineTests`' own `PauseGate`, giving a real,
/// deterministic point to change the root from and check cancellation
/// against, rather than racing a hopeful "change it immediately" against
/// the search's own scheduling.
private actor PauseGate {
    private var isPaused = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var pausedContinuations: [CheckedContinuation<Void, Never>] = []

    func waitUntilReleased() async {
        isPaused = true
        for continuation in pausedContinuations {
            continuation.resume()
        }
        pausedContinuations.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilPaused() async {
        if isPaused {
            return
        }
        await withCheckedContinuation { pausedContinuations.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

/// Counts how many times a stub `performSearch` was actually invoked, for
/// asserting a debounce genuinely coalesced multiple scheduling attempts
/// into fewer real calls.
private actor CallCounter {
    private(set) var value = 0
    func increment() {
        value += 1
    }
}

/// A settable flag with a real wait point, used to deterministically
/// observe a value set from inside an async closure without polling.
private actor ObservedBool {
    private(set) var value = false
    private var continuation: CheckedContinuation<Void, Never>?

    func set(_ newValue: Bool) {
        value = newValue
        continuation?.resume()
        continuation = nil
    }

    func waitForSet(timeout _: Duration = .seconds(5)) async {
        guard !value else { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

/// A real wall-clock deadline, not a fixed iteration/yield-count budget —
/// same shape as `QuickOpenModelTests`' own `waitUntil` helper.
@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor @Sendable () -> Bool,
    timeout: Duration = .seconds(5)
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for FolderSearchModel to settle")
}
