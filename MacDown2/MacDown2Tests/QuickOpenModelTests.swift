import Foundation
@testable import MacDown2
import Testing
import TextSearch

/// EPIC-22 §6.15, Slice 6b — `QuickOpenModel`'s own pure query/selection
/// logic, mirroring `CommandPaletteModelTests`' own separation of model
/// tests from panel/view presentation. Uses a real, small temp directory
/// tree and `WorkspaceFileIndex`'s own public `rebuild(root:)` rather than
/// its package-internal `seedForTesting` seam (that seam is reserved for
/// `TextSearchTests`' own 100k-path performance test, in the same module as
/// `WorkspaceFileIndex` itself; a real small tree is both simpler here and
/// exercises the actual end-to-end `rebuild` → `query` path).
@Suite("QuickOpenModel")
@MainActor
struct QuickOpenModelTests {
    private final class TempTree {
        let root: URL

        init(_ files: [String]) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for relativePath in files {
                let url = root.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data().write(to: url)
            }
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test func refreshWithNoQueryShowsIndexedFiles() async throws {
        let tree = try TempTree(["a.md", "b.swift"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)

        model.refresh()
        await waitUntil { model.results.count == 2 }

        #expect(Set(model.results.map(\.relativePath)) == ["a.md", "b.swift"])
    }

    @Test func queryFuzzyFiltersTheIndexedFiles() async throws {
        let tree = try TempTree(["WindowCoordinator.swift", "unrelated.txt"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)

        model.query = "wico"
        await waitUntil { model.results.count == 1 }

        #expect(model.results.first?.relativePath == "WindowCoordinator.swift")
    }

    @Test func rapidTypingEndsOnTheLastTypedQuerysResults() async throws {
        // A real end-to-end smoke test that typing two characters in a row
        // settles on the LAST one's results -- but against the real
        // `WorkspaceFileIndex` actor, whose calls are always processed (and
        // therefore always COMPLETE) in the order they were submitted, this
        // alone cannot distinguish "the generation guard correctly
        // discarded a late, stale result" from "the two queries just
        // happened to finish in submission order anyway", since a single
        // actor never lets that order invert on its own. See
        // `lateArrivingStaleQueryResultIsDiscarded` below for a test that
        // actually forces and proves the inversion the guard exists to
        // handle (an independent hostile review of this exact test found
        // it passed unchanged even with the generation guard deleted
        // entirely).
        let tree = try TempTree(["apple.txt", "banana.txt"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)

        model.query = "app"
        model.query = "ban"
        await waitUntil { model.results.count == 1 }

        #expect(model.results.first?.relativePath == "banana.txt")
    }

    @Test func lateArrivingStaleQueryResultIsDiscarded() async {
        // Forces the exact completion-order inversion
        // `QuickOpenModel.scheduleQuery()`'s generation counter exists to
        // handle -- a NEWER query's result committing before an OLDER,
        // now-superseded query's result arrives late -- via a controllable
        // `performRead` seam instead of the real `WorkspaceFileIndex`
        // actor (whose own call-ordering guarantees make this inversion
        // impossible to observe naturally; see the sibling test above).
        let gate = QueryGate()
        let staleResult = [IndexedPath(relativePath: "stale.txt", basename: "stale.txt")]
        let freshResult = [IndexedPath(relativePath: "fresh.txt", basename: "fresh.txt")]
        let model = QuickOpenModel(performRead: { query in await gate.hold(query) })

        model.query = "app" // generation 1 -- will resolve to staleResult, held for now
        model.query = "ban" // generation 2 -- will resolve to freshResult, held for now

        // Both `Task`s spawned by the two `scheduleQuery()` calls above are
        // merely CREATED at this point, not necessarily already running --
        // releasing a query before its own `hold(_:)` call has actually
        // registered would silently no-op (nothing pending to resume yet),
        // then strand that query's real, later `hold(_:)` call waiting on a
        // release that already "happened". Waiting for both to genuinely
        // be pending first closes that race.
        await gate.waitUntilPending("app")
        await gate.waitUntilPending("ban")

        // Resolve the NEWER query first, exactly the inversion a real
        // single-actor index could never produce on its own.
        await gate.release("ban", with: freshResult)
        await waitUntil { model.results == freshResult }

        // Now let the OLDER, already-superseded query complete LATE. A
        // broken (or deleted) generation guard would let this overwrite
        // the newer, already-committed result.
        await gate.release("app", with: staleResult)
        await Task.yield()

        #expect(model.results == freshResult, "a late-arriving stale query result must not overwrite the newer one")
    }

    @Test func rowsFromThePreviousQueryAreNotActionableWhileANewQueryIsPending() async {
        let gate = QueryGate()
        let oldRows = [IndexedPath(relativePath: "old.txt", basename: "old.txt")]
        let newRows = [IndexedPath(relativePath: "new.txt", basename: "new.txt")]
        let model = QuickOpenModel(performRead: { query in await gate.hold(query) })

        model.query = "old"
        await gate.waitUntilPending("old")
        await gate.release("old", with: oldRows)
        await waitUntil { model.results == oldRows }
        #expect(model.selectedResult?.path == oldRows.first)

        model.query = "new" // the old rows are still displayed, but belong to the previous query
        await gate.waitUntilPending("new")
        #expect(model.results == oldRows)
        #expect(model.selectedResult == nil, "Return/click must not open a row from the superseded query")

        await gate.release("new", with: newRows)
        await waitUntil { model.results == newRows }
        #expect(model.selectedResult?.path == newRows.first)
    }

    @Test func anUnavailableIndexIsReportedDistinctlyFromNoMatches() async {
        let unavailable = UnavailableFlag()
        let model = QuickOpenModel(performRead: { _ in
            let isUnavailable = await unavailable.value
            return .init(paths: [], isUnavailable: isUnavailable)
        })

        model.refresh()
        await waitUntil { !model.isSearching }
        #expect(!model.isIndexUnavailable, "an empty result from a healthy index is just 'no matches'")

        await unavailable.set(true)
        model.query = "x"
        await waitUntil { model.isIndexUnavailable }
        #expect(model.results.isEmpty)
    }

    @Test func lateUnavailableReadCannotReplaceANewerReadyRead() async {
        let gate = QueryGate()
        let fresh = [IndexedPath(relativePath: "fresh.txt", basename: "fresh.txt")]
        let model = QuickOpenModel(performRead: { query in await gate.hold(query) })

        model.query = "old"
        model.query = "new"
        await gate.waitUntilPending("old")
        await gate.waitUntilPending("new")
        await gate.release("new", with: fresh)
        await waitUntil { model.results == fresh && !model.isSearching }
        await gate.release("old", with: [], unavailable: true)
        await Task.yield()

        #expect(model.results == fresh)
        #expect(!model.isIndexUnavailable)
    }

    @Test func moveSelectionWrapsAroundInBothDirections() async throws {
        let tree = try TempTree(["a.txt", "b.txt"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)
        model.refresh()
        await waitUntil { model.results.count == 2 }
        #expect(model.selectedIndex == 0)

        model.moveSelection(by: -1)
        #expect(model.selectedIndex == 1)

        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 0)
    }

    @Test func moveSelectionOnAnEmptyResultListDoesNothing() async throws {
        let tree = try TempTree(["a.txt"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)

        model.query = "nonexistent"
        await waitUntil { model.results.isEmpty && !model.isSearching }

        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 0)
    }

    @Test func selectedResultReflectsTheCurrentSelectionIndex() async throws {
        let tree = try TempTree(["a.txt", "b.txt"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)
        model.refresh()
        await waitUntil { model.results.count == 2 }

        model.moveSelection(by: 1)

        #expect(model.selectedResult?.path.relativePath == model.results[1].relativePath)
    }

    @Test func rebuiltIndexRejectsDisplayedRowEvenWhenTheSamePathReturns() async throws {
        let tree = try TempTree(["same.md"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = QuickOpenModel(index: index)
        model.refresh()
        await waitUntil { model.selectedResult != nil }
        let selected = try #require(model.selectedResult)
        let origin = QuickOpenOrigin(generation: 1, lexicalRoot: tree.root, accessRoot: tree.root)
        let originBox = QuickOpenOriginBox(origin)
        let gate = QuickOpenActionGate(index: index) { originBox.current }
        #expect(await gate.admit(selected, from: origin))

        await index.rebuild(root: tree.root)
        #expect(await !(gate.admit(selected, from: origin)))
        model.refresh()
        await waitUntil {
            model.selectedResult.map { $0.publishedGeneration != selected.publishedGeneration } ?? false
        }
        let refreshed = try #require(model.selectedResult)
        #expect(refreshed.path.relativePath == selected.path.relativePath)
        #expect(await gate.admit(refreshed, from: origin))
    }

    @Test func rootSwitchDuringIndexAdmissionRejectsClickedRow() async {
        let oldRoot = URL(fileURLWithPath: "/tmp/quick-open-old")
        let newRoot = URL(fileURLWithPath: "/tmp/quick-open-new")
        let origin = QuickOpenOrigin(generation: 1, lexicalRoot: oldRoot, accessRoot: oldRoot)
        let originBox = QuickOpenOriginBox(origin)
        let pause = QuickOpenAdmissionPause()
        let gate = QuickOpenActionGate(
            indexAdmission: { _ in await pause.hold() },
            currentOrigin: { originBox.current }
        )
        let selected = QuickOpenModel.PresentedResult(
            path: IndexedPath(relativePath: "same.md", basename: "same.md"),
            publishedGeneration: 1,
            queryGeneration: 1
        )
        let action = Task { await gate.admit(selected, from: origin) }
        await pause.waitUntilPending()
        originBox.current = QuickOpenOrigin(generation: 2, lexicalRoot: newRoot, accessRoot: newRoot)
        await pause.resume(with: true)

        #expect(await !(action.value))
    }
}

@MainActor
private final class QuickOpenOriginBox {
    var current: QuickOpenOrigin?

    init(_ origin: QuickOpenOrigin) {
        current = origin
    }
}

private actor QuickOpenAdmissionPause {
    private var pending: CheckedContinuation<Bool, Never>?
    private var released: Bool?

    func hold() async -> Bool {
        if let released {
            return released
        }
        return await withCheckedContinuation { pending = $0 }
    }

    func waitUntilPending() async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while clock.now < deadline {
            if pending != nil {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for Quick Open action admission")
    }

    func resume(with result: Bool) {
        released = result
        pending?.resume(returning: result)
        pending = nil
    }
}

/// A controllable stand-in for `WorkspaceFileIndex.query(_:limit:)`: each
/// distinct query string is held (via a real continuation, not a fixed
/// delay) until the test explicitly releases it with a chosen result,
/// letting a test force any completion order it wants — including one a
/// real single actor's own call-ordering guarantees could never produce.
private actor QueryGate {
    private var pending: [String: CheckedContinuation<QuickOpenModel.IndexRead, Never>] = [:]

    func hold(_ query: String) async -> QuickOpenModel.IndexRead {
        await withCheckedContinuation { pending[query] = $0 }
    }

    func release(_ query: String, with result: [IndexedPath], unavailable: Bool = false) {
        pending.removeValue(forKey: query)?.resume(returning: .init(paths: result, isUnavailable: unavailable))
    }

    /// Waits until `query`'s own `hold(_:)` call has actually registered
    /// its continuation — a real wall-clock deadline, not a fixed
    /// iteration/yield-count budget, same shape as this file's own
    /// `waitUntil`. Closes the "release before hold" race `release(_:with:)`
    /// would otherwise silently no-op on: a `Task` spawned by
    /// `QuickOpenModel.scheduleQuery()` is merely CREATED when that method
    /// returns, not necessarily already running.
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

/// A real wall-clock deadline, not a fixed iteration/yield-count budget —
/// same shape as `DocumentFileMonitorTests.swift`'s own `waitUntil` helper,
/// needed here because `QuickOpenModel.scheduleQuery()` resolves
/// asynchronously against the `WorkspaceFileIndex` actor. The condition is
/// `@MainActor`, not a plain `@Sendable` async closure, because
/// `QuickOpenModel` is a `@MainActor` class (its properties need actor
/// isolation to read, not an `await` on the class itself the way an actor's
/// properties would).
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
    Issue.record("Timed out waiting for QuickOpenModel to settle")
}

private actor UnavailableFlag {
    private(set) var value = false
    func set(_ newValue: Bool) {
        value = newValue
    }
}
