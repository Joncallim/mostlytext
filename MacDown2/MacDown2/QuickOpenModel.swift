import Foundation
import Observation
import TextSearch

/// Pure query/selection logic for Quick Open (EPIC-22 §6.15, Slice 6b),
/// kept free of any AppKit/SwiftUI presentation so it is directly testable
/// without presenting UI — mirrors `CommandPaletteModel`'s same separation.
///
/// Unlike `CommandPaletteModel`'s `applyFilter()`, which is synchronous,
/// pure in-memory filtering, `WorkspaceFileIndex.query(_:limit:)` is an
/// actor call: querying it is `async`, so `query`'s own `didSet` cannot
/// filter synchronously the way the palette's does. Each edit spawns a new
/// `Task` and bumps `queryGeneration`, discarding any now-superseded
/// in-flight call's result — the same query-generation-counter discipline
/// `EditorFindModel.updateMatches` already established for exactly this
/// shape of problem (§8).
@MainActor
@Observable
final class QuickOpenModel {
    struct IndexRead: Sendable {
        let paths: [IndexedPath]
        let isUnavailable: Bool
        let publishedGeneration: UInt64

        init(paths: [IndexedPath], isUnavailable: Bool, publishedGeneration: UInt64 = 0) {
            self.paths = paths
            self.isUnavailable = isUnavailable
            self.publishedGeneration = publishedGeneration
        }
    }

    /// A displayed row bound to the index publication that produced it.
    /// The action path checks this token again after its actor hop.
    struct PresentedResult: Sendable, Equatable {
        let path: IndexedPath
        let publishedGeneration: UInt64
        let queryGeneration: Int
    }

    var query = "" {
        didSet {
            // SwiftUI may write the field's unchanged value again while
            // submitting. That must not invalidate the selected row token.
            if query != oldValue {
                scheduleQuery()
            }
        }
    }

    private(set) var results: [IndexedPath] = []
    private(set) var selectedIndex = 0
    private(set) var isSearching = false
    /// True when the workspace index failed (its folder vanished or became
    /// unreadable) rather than the query merely matching nothing (#183 F18).
    private(set) var isIndexUnavailable = false
    private var resultsPublishedGeneration: UInt64 = 0

    private let performRead: @Sendable (String) async -> IndexRead
    private var queryGeneration = 0

    /// `recentRelativePaths` implements issue #112's "Recent-file history
    /// feeds Quick Open ranking" (Slice 6c) — computed once by the caller
    /// (`QuickOpenPanel.init`, from `RecentFileDocuments.relativePaths(under:)`)
    /// at panel-open time, not re-read live for the panel's whole lifetime:
    /// a short-lived filtering session has no real staleness concern, and
    /// `WorkspaceFileIndex.query` itself already has no other reason to
    /// accept live, ongoing state.
    init(index: WorkspaceFileIndex, recentRelativePaths: Set<String> = []) {
        performRead = { query in
            let snapshot = await index.querySnapshot(query, limit: 100, recentRelativePaths: recentRelativePaths)
            if case .failed = snapshot.state {
                return IndexRead(
                    paths: snapshot.paths,
                    isUnavailable: true,
                    publishedGeneration: snapshot.publishedGeneration
                )
            }
            return IndexRead(
                paths: snapshot.paths,
                isUnavailable: false,
                publishedGeneration: snapshot.publishedGeneration
            )
        }
    }

    /// Test-only seam: substitutes one caller-controlled status-and-path read
    /// for the real `WorkspaceFileIndex.querySnapshot(_:limit:)` call, matching this
    /// project's established injectable-dependency shape for testing
    /// actor-based async work deterministically (`DocumentFileMonitor`'s
    /// injectable `sleeper`/`prober`/`watcher`, `WorkspaceFileIndex`'s own
    /// injectable `walk`). Needed because `WorkspaceFileIndex` is a single
    /// actor whose calls are always processed in the order they're
    /// submitted — two real queries issued back to back always COMPLETE in
    /// that same order too, so a test built only on the real actor cannot
    /// distinguish "the generation guard correctly discarded a late,
    /// stale result" from "the two queries just happened to finish in
    /// submission order anyway" (a hostile review of this exact slice
    /// proved this empirically: deleting the generation guard entirely
    /// still left every existing test passing). This seam lets a test
    /// force the actual inversion the guard exists to handle — a newer
    /// query's result committed before an older, now-stale query's
    /// late-arriving one — via controlled continuations.
    init(performRead: @escaping @Sendable (String) async -> IndexRead) {
        self.performRead = performRead
    }

    /// Runs the current query once against the index. Intended to be called
    /// once per panel opening (its one call site is `QuickOpenView.onAppear`)
    /// — matching `CommandPaletteModel.refreshRows()`'s own "one real scan
    /// per opening, not one per keystroke" discipline — so the panel shows
    /// an initial result set (an empty query returns the index's own
    /// front-of-snapshot files, per `WorkspaceFileIndex.query`'s own
    /// documented empty-query behavior) the instant it appears.
    func refresh() {
        scheduleQuery()
    }

    private func scheduleQuery() {
        queryGeneration += 1
        let generation = queryGeneration
        let currentQuery = query
        isSearching = true
        Task {
            let read = await performRead(currentQuery)
            guard generation == queryGeneration else { return } // superseded by a newer query
            results = read.paths
            isIndexUnavailable = read.isUnavailable
            resultsPublishedGeneration = read.publishedGeneration
            selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)
            isSearching = false
        }
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let count = results.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    /// The row Return/click would open. `nil` while a newer query is still
    /// pending: until its response lands, `results` belong to the PREVIOUS
    /// query, and acting on one would open a file the user's current text no
    /// longer asks for (#183 F19).
    var selectedResult: PresentedResult? {
        guard !isSearching, let path = results[safe: selectedIndex] else { return nil }
        return PresentedResult(
            path: path,
            publishedGeneration: resultsPublishedGeneration,
            queryGeneration: queryGeneration
        )
    }
}

/// The exact window/root request behind a Quick Open panel. The panel closes
/// on root changes, and this value independently guards asynchronous opens.
struct QuickOpenOrigin: Equatable, Sendable {
    let generation: UInt
    let lexicalRoot: URL
    let accessRoot: URL
}

/// Checks both the displayed index publication and the origin folder after
/// the index actor hop. The injected admission closure lets a test pause at
/// that hop and force a root switch before the final identity check.
@MainActor
struct QuickOpenActionGate {
    private let indexAdmission: @Sendable (QuickOpenModel.PresentedResult) async -> Bool
    private let currentOrigin: @MainActor () -> QuickOpenOrigin?

    init(index: WorkspaceFileIndex, currentOrigin: @escaping @MainActor () -> QuickOpenOrigin?) {
        indexAdmission = { result in
            await index.isActionable(result.path, publishedGeneration: result.publishedGeneration)
        }
        self.currentOrigin = currentOrigin
    }

    init(
        indexAdmission: @escaping @Sendable (QuickOpenModel.PresentedResult) async -> Bool,
        currentOrigin: @escaping @MainActor () -> QuickOpenOrigin?
    ) {
        self.indexAdmission = indexAdmission
        self.currentOrigin = currentOrigin
    }

    func isCurrent(_ origin: QuickOpenOrigin) -> Bool {
        currentOrigin() == origin
    }

    func admit(_ result: QuickOpenModel.PresentedResult, from origin: QuickOpenOrigin) async -> Bool {
        guard isCurrent(origin), await indexAdmission(result) else { return false }
        return isCurrent(origin)
    }
}
