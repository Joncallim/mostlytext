import FileCore
import Foundation

/// One file's worth of folder-search results. `revision` is the file's
/// state exactly as read for this search — the same value a later Replace
/// in Folder plan (Slice 7c) captures as its own per-file `expectedRevision`
/// baseline, so a file that changed between search and replace is detected
/// rather than silently overwritten (issue #112, invariant #6).
public struct FolderSearchMatch: Sendable, Equatable {
    public let relativePath: String
    public let matches: [SearchMatch]
    public let revision: FileRevision

    public init(relativePath: String, matches: [SearchMatch], revision: FileRevision) {
        self.relativePath = relativePath
        self.matches = matches
        self.revision = revision
    }
}

/// How a `WorkspaceSearchEngine.search` call ended. `filesSkipped` counts
/// every file `FileStore.readSnapshot` could not turn into text — binary/
/// non-decodable content, a permission error, a symlink pointing at a
/// non-regular file (`FileStore`'s own pre-existing `.notRegularFile`
/// guard) — collapsed into one count rather than surfaced per-error-case,
/// since a folder search's own UI (Slice 7b) reports "N files could not be
/// searched," not a taxonomy of why.
public enum FolderSearchOutcome: Sendable, Equatable {
    case completed(filesSearched: Int, filesSkipped: Int, matchCount: Int)
    /// `maxMatches` was reached before every candidate file was visited —
    /// issue #112's own "bounded accumulation" with "explicit truncation,"
    /// never a silent cap. `filesSearched` only counts files actually
    /// searched before truncation, not the full candidate set.
    case truncated(filesSearched: Int, filesSkipped: Int, matchCount: Int)
    case cancelled
    /// The query failed to compile as a regex — a property of the QUERY,
    /// not any one file, detected once up front before any file is touched.
    case invalidRegex(String)
    /// The workspace index failed (its folder vanished or became unreadable),
    /// so "no results" would be a lie: nothing was searched (#183 F18).
    case indexUnavailable
}

/// Folder-wide search orchestration over paths a `WorkspaceFileIndex`
/// already knows about (EPIC-22 issue #112, Slice 7a). An `actor`,
/// mirroring `WorkspaceFileIndex`'s own concurrency shape — a caller
/// launches `search` from a `Task` it can cancel to abandon an in-flight
/// search early (a superseded query, a dismissed panel, a changed root).
///
/// Reuses Slice 5's `SearchOptions`/`SearchMatch`/`TextSearchEngine`
/// verbatim — no second query-options type — and `FileStore.readSnapshot`
/// (`FileCore`) for every per-file read, so binary detection, encoding
/// detection, and the symlink-unfriendly `.notRegularFile` guard are the
/// same ones `FileStore` already established, not reimplemented here.
/// Directory-level exclusion (`.git`, `node_modules`, etc.) already
/// happened once when the index itself was built
/// (`WorkspaceFileIndex.defaultExcludedDirectoryNames`); a symlink LOOP
/// during that walk is likewise already guarded by
/// `DirectoryWalker`'s own `visited` set — neither is repeated here (see
/// `WorkspaceSearchEngineTests.searchingAWorkspaceContainingASymlinkLoopCompletesAndFindsTheRealFile`,
/// which proves this engine inherits that guard rather than needing its
/// own).
public actor WorkspaceSearchEngine {
    /// A generous default — large enough that an ordinary project's search
    /// never hits it, small enough that a genuinely pathological query (a
    /// single common character across a huge tree) cannot grow the result
    /// set without bound before the caller even sees the first result.
    public static let defaultMaxMatches = 5000

    /// Test-only injectable seams (package-internal, not part of the public
    /// API), bundled into one struct so `init(seams:)` can stay a single,
    /// always-non-optional-parameter overload distinct from `public init()`
    /// — three individually-defaulted closures would make `init()` itself
    /// ambiguous between the public and test-only initializers.
    struct TestSeams: Sendable {
        /// Pauses after the one index snapshot has been captured, so a test
        /// can change the index before the search consumes that snapshot.
        var afterIndexSnapshot: (@Sendable () async -> Void)?
        /// Called once per file, immediately before that file's own
        /// cancellation check — mirrors `WorkspaceFileIndex`'s own
        /// established `init(walk:)` injectable-dependency precedent for
        /// testing actor-based async work deterministically. A real
        /// caller's own `Task.cancel()` races `search`'s own loop with no
        /// guaranteed ordering (confirmed empirically: a naive "cancel
        /// immediately after creating the task" test was found to let 2 of
        /// 200 files through before the cancellation flag was observed), so
        /// a genuine test of "cancelling produces no result" needs a real
        /// pause point to cancel from, not a hopeful race.
        var beforeEachFile: (@Sendable () async -> Void)?
        /// Called once per file that was actually read, immediately after
        /// that file's own matches have been computed but before they are
        /// published — the pause point a test needs to prove that
        /// cancellation discovered AFTER a (possibly slow) per-file match is
        /// still honored: without this seam, a naive test can only cancel
        /// BEFORE a file starts, never mid-file, so it could never have
        /// caught the gap this seam's own test
        /// (`cancellingAfterAFilesMatchesAreComputedDiscardsThatFilesResult`)
        /// exists to close.
        var afterMatchingFile: (@Sendable () async -> Void)?
        /// Substitutes the real `FileStore.readSnapshot` call for one
        /// specific path (returning the real read for every other path) —
        /// lets a permission-failure test be deterministic rather than
        /// depending on `chmod`'s own platform/sandbox-dependent timing
        /// (a sandboxed test runner, or running as root, can silently
        /// ignore permission bits entirely).
        var readSnapshot: (@Sendable (URL, IndexedPath) -> FileSnapshot?)?
    }

    private let seams: TestSeams

    public init() {
        seams = TestSeams()
    }

    init(seams: TestSeams) {
        self.seams = seams
    }

    /// Streams one `FolderSearchMatch` per file with at least one match, in
    /// `index`'s own indexed order, `await`-ing `onMatch` for each before
    /// moving on to the next file — never buffering the whole result set
    /// internally, so a caller can render results as they arrive rather
    /// than waiting for the whole tree to finish. `onMatch` is itself
    /// `async` (not fire-and-forget) so a caller that needs to hop across
    /// an actor boundary to record a result (a `@MainActor` view model,
    /// say) can do so deterministically, with `search` itself not moving on
    /// to the next file until that hop completes — no unstructured `Task`
    /// the engine has no way to wait for.
    ///
    /// Cancellation is checked at three points per file, not just one:
    /// before it is read (between files), immediately after its matches are
    /// computed (a slow regex against a large file is exactly where a
    /// superseded search must still stop promptly, even though
    /// `TextSearchEngine`'s own `NSRegularExpression`-backed matching has no
    /// cooperative-cancellation hook mid-evaluation), and immediately after
    /// the awaited `onMatch` callback returns — so a cancellation observed
    /// during any of those three windows always yields `.cancelled` with no
    /// further file's result published, never a late `.completed`/
    /// `.truncated` outcome carrying one extra, stale result computed after
    /// the caller had already moved on (a changed workspace root, a
    /// superseded query generation).
    ///
    /// Bounded accumulation (issue #112) is enforced at the matching layer
    /// itself, not just by truncating an already-fully-computed result
    /// afterward: each file is matched with `TextSearchEngine`'s own
    /// `matchLimit` set to this file's remaining share of `maxMatches`, so
    /// a single pathological file (millions of matches) can never force an
    /// unbounded `[SearchMatch]` allocation before its result is capped.
    public func search(
        root: URL,
        index: WorkspaceFileIndex,
        query: String,
        options: SearchOptions,
        filter: FolderSearchFilter = FolderSearchFilter(),
        maxMatches: Int = WorkspaceSearchEngine.defaultMaxMatches,
        onMatch: @escaping @Sendable (FolderSearchMatch) async -> Void
    ) async -> FolderSearchOutcome {
        guard !query.isEmpty else { return .completed(filesSearched: 0, filesSkipped: 0, matchCount: 0) }

        // Validate the regex exactly once, against an empty buffer, before
        // touching any file: a compile failure is a property of the
        // pattern alone (`NSRegularExpression` compilation never depends on
        // the text it is later run against), so this both fails fast and
        // avoids silently recompiling the same pattern once per candidate
        // file below.
        switch Self.validate(query: query, options: options) {
        case let .invalid(message):
            return .invalidRegex(message)
        case .valid:
            break
        }

        let snapshot = await index.allPathsSnapshot(includeHidden: filter.includeHidden)
        await seams.afterIndexSnapshot?()
        if case .failed = snapshot.state {
            return .indexUnavailable
        }
        let paths = snapshot.paths
        let context = SearchContext(root: root, query: query, options: options, filter: filter)
        var filesSearched = 0
        var filesSkipped = 0
        var totalMatches = 0

        for path in paths {
            await seams.beforeEachFile?()
            if Task.isCancelled {
                return .cancelled
            }

            let remaining = maxMatches - totalMatches
            guard remaining > 0 else {
                return .truncated(filesSearched: filesSearched, filesSkipped: filesSkipped, matchCount: totalMatches)
            }

            let stepOutcome = await processFile(path, context: context, remaining: remaining, onMatch: onMatch)
            switch apply(
                stepOutcome,
                filesSearched: &filesSearched,
                filesSkipped: &filesSkipped,
                totalMatches: &totalMatches
            ) {
            case .keepGoing:
                continue
            case let .stop(outcome):
                return outcome
            }
        }

        return .completed(filesSearched: filesSearched, filesSkipped: filesSkipped, matchCount: totalMatches)
    }

    /// The per-file inputs that stay constant across one whole `search`
    /// call, bundled so `processFile` takes one value instead of four
    /// separate parameters (SwiftLint's `function_parameter_count` limit).
    private struct SearchContext {
        let root: URL
        let query: String
        let options: SearchOptions
        let filter: FolderSearchFilter
    }

    private enum FileStepOutcome {
        case skippedByFilter
        case skippedUnreadable
        case cancelled
        case noMatches
        case published(matchCount: Int, wasCapped: Bool)
    }

    private enum LoopSignal {
        case keepGoing
        case stop(FolderSearchOutcome)
    }

    /// Turns one file's `FileStepOutcome` into the loop's own counter
    /// updates and next action, so `search`'s own body stays a plain
    /// dispatch instead of absorbing this switch's own branching into its
    /// cyclomatic complexity (SwiftLint's `cyclomatic_complexity` limit).
    private func apply(
        _ stepOutcome: FileStepOutcome,
        filesSearched: inout Int,
        filesSkipped: inout Int,
        totalMatches: inout Int
    ) -> LoopSignal {
        switch stepOutcome {
        case .skippedByFilter:
            return .keepGoing
        case .skippedUnreadable:
            filesSkipped += 1
            return .keepGoing
        case .cancelled:
            return .stop(.cancelled)
        case .noMatches:
            filesSearched += 1
            return .keepGoing
        case let .published(matchCount, wasCapped):
            filesSearched += 1
            totalMatches += matchCount
            guard wasCapped else { return .keepGoing }
            return .stop(.truncated(filesSearched: filesSearched, filesSkipped: filesSkipped, matchCount: totalMatches))
        }
    }

    /// Searches exactly one file and reports what happened, so `search`'s
    /// own loop stays a plain dispatch over this outcome rather than a
    /// 50+-line body (SwiftLint's `function_body_length` limit) mixing
    /// per-file mechanics with the loop's own counter bookkeeping.
    /// `remaining` is this file's own share of the total `maxMatches`
    /// budget still available — used both to bound `TextSearchEngine`'s own
    /// per-file matching (never materializing more than one match beyond
    /// what could ever be published) and to decide whether this file's
    /// result is itself the one that trips truncation.
    private func processFile(
        _ path: IndexedPath,
        context: SearchContext,
        remaining: Int,
        onMatch: @escaping @Sendable (FolderSearchMatch) async -> Void
    ) async -> FileStepOutcome {
        guard context.filter.matches(path) else { return .skippedByFilter }
        guard let snapshot = readSnapshot(root: context.root, path: path) else { return .skippedUnreadable }

        // `remaining + 1`, not `remaining`: lets a file with exactly
        // `remaining` matches be distinguished from one with MORE than
        // `remaining` (truncation), while still bounding the matcher's own
        // per-file work to at most one match beyond what could ever
        // actually be published.
        let found = Self.matches(
            in: snapshot.text,
            query: context.query,
            options: context.options,
            matchLimit: remaining + 1
        )
        await seams.afterMatchingFile?()
        if Task.isCancelled {
            return .cancelled
        }
        guard !found.isEmpty else { return .noMatches }

        let capped = found.count > remaining ? Array(found.prefix(remaining)) : found
        await onMatch(FolderSearchMatch(relativePath: path.relativePath, matches: capped, revision: snapshot.revision))
        if Task.isCancelled {
            return .cancelled
        }
        return .published(matchCount: capped.count, wasCapped: capped.count < found.count)
    }

    private func readSnapshot(root: URL, path: IndexedPath) -> FileSnapshot? {
        if let override = seams.readSnapshot {
            return override(root, path)
        }
        return Self.readSnapshot(root: root, path: path)
    }

    /// The index lists every regular file, so a search over a folder holding a video or a disk image would read
    /// and hash all of it (1.4 s for a 1.5 GB file, on every debounced keystroke). Larger files are skipped and
    /// counted as unreadable, like any other file that cannot be searched as text.
    static let maximumSearchableFileSize = 32 * 1024 * 1024

    private static func readSnapshot(root: URL, path: IndexedPath) -> FileSnapshot? {
        let url = root.appendingPathComponent(path.relativePath)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumSearchableFileSize {
            return nil
        }
        return try? FileStore().readSnapshot(from: url)
    }

    /// Already validated to compile once, up front, in `search` itself; the
    /// only error `TextSearchEngine.matches` can throw is a regex compile
    /// failure, which cannot happen twice for an unchanged pattern+options
    /// pair, so this collapses that (unreachable in practice) case to "no
    /// matches" rather than threading a second error path through here.
    private static func matches(
        in text: String,
        query: String,
        options: SearchOptions,
        matchLimit: Int
    ) -> [SearchMatch] {
        (try? TextSearchEngine.matches(in: text, query: query, options: options, matchLimit: matchLimit)) ?? []
    }

    private enum ValidationResult {
        case valid
        case invalid(String)
    }

    private static func validate(query: String, options: SearchOptions) -> ValidationResult {
        do {
            _ = try TextSearchEngine.matches(in: "", query: query, options: options)
            return .valid
        } catch {
            // `matches`'s own typed throw (`throws(SearchQueryError)`) means
            // `error` here is statically `SearchQueryError`, whose only
            // case is `.invalidRegex` -- an exhaustive switch, not a
            // dead-code-hiding generic catch-all.
            switch error {
            case let .invalidRegex(message):
                return .invalid(message)
            case .cancelled:
                // Validation ran inside an already-cancelled search; the caller
                // checks cancellation itself right after.
                return .valid
            }
        }
    }
}
