import FileCore
import Foundation
import Testing
@testable import TextSearch

@Suite("WorkspaceReplaceEngine safety")
struct WorkspaceReplaceSafetyTests {
    @Test
    func unexpectedWriteFailureUsesActionableCopyWithoutRawErrorDetails() {
        let underlying = NSError(domain: "PrivateStorageDetails", code: 42)
        let outcome = WorkspaceReplaceEngine.outcome(
            forWriteError: .writeFailed(underlying: underlying),
            url: URL(fileURLWithPath: "/tmp/example.md"), updated: "replacement", count: 1
        )
        guard case let .failed(message) = outcome else {
            Issue.record("unexpected write failure must remain failed")
            return
        }
        #expect(message == "The replacement could not be confirmed. Check the file before retrying.")
        #expect(!message.contains("PrivateStorageDetails"))
        #expect(!message.contains("writeFailed"))
    }

    @Test
    func aFileEditedAfterTheSearchIsSkippedAndLeftUntouched() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("stale.md", text: "foo one")
        try tree.write("fresh.md", text: "foo two")
        let results = await searchResults(tree, query: "foo")
        try tree.write("stale.md", text: "inserted foo one")

        let outcomes = await WorkspaceReplaceEngine().replace(
            root: tree.root,
            plans: plans(results, replacement: "bar")
        )

        let byPath = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.relativePath, $0.outcome) })
        #expect(byPath["stale.md"] == .skippedChangedSinceSearch)
        #expect(byPath["fresh.md"] == .replaced(count: 1))
        #expect(try read(tree, "stale.md") == "inserted foo one")
        #expect(try read(tree, "fresh.md") == "bar two")
    }

    @Test
    func aWriterThatWinsBetweenTheVerifyingReadAndPublicationIsNeverOverwritten() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "foo original")
        let results = await searchResults(tree, query: "foo")
        let external = "EXTERNAL EDIT (longer than the original)"
        var seams = WorkspaceReplaceEngine.TestSeams()
        seams.beforeWrite = { url in try? external.write(to: url, atomically: false, encoding: .utf8) }

        let outcomes = await WorkspaceReplaceEngine(seams: seams).replace(
            root: tree.root,
            plans: plans(results, replacement: "bar")
        )

        #expect(outcomes.first?.outcome == .skippedChangedSinceSearch)
        #expect(try read(tree, "a.md") == external)
    }

    @Test
    func aReviewedFileMovedOutsideTheRootBeforePublicationIsNotRewritten() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("dir/a.md", text: "foo original")
        let results = await searchResults(tree, query: "foo")
        let child = tree.root.appendingPathComponent("dir", isDirectory: true)
        let outside = tree.root.deletingLastPathComponent()
            .appendingPathComponent("moved-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        var seams = WorkspaceReplaceEngine.TestSeams()
        seams.beforeWrite = { _ in
            try? FileManager.default.moveItem(at: child, to: outside)
            try? FileManager.default.createSymbolicLink(at: child, withDestinationURL: outside)
        }

        let outcomes = await WorkspaceReplaceEngine(seams: seams).replace(
            root: tree.root, plans: plans(results, replacement: "bar")
        )

        #expect(outcomes.first?.outcome != .replaced(count: 1))
        #expect(try String(contentsOf: outside.appendingPathComponent("a.md"), encoding: .utf8) == "foo original")
    }

    @Test
    func symbolicLinkedFilesAreNeverRewrittenThroughTheLink() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("real.md", text: "foo target")
        let link = tree.root.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: tree.root.appendingPathComponent("real.md")
        )
        // `FileStore.readSnapshot` itself refuses a link, so a folder search
        // never yields one; a plan for it can only be hand-built, and must
        // still never be written through.
        let snapshot = try FileStore().readSnapshot(from: tree.root.appendingPathComponent("real.md"))
        let plan = ReplacementPlan(
            relativePath: "link.md",
            revision: snapshot.revision,
            matches: [SearchMatch(range: NSRange(location: 0, length: 3))],
            replacementText: "bar"
        )

        let outcomes = await WorkspaceReplaceEngine().replace(root: tree.root, plans: [plan])

        #expect(outcomes.first?.outcome == .skippedSymbolicLink)
        #expect(try read(tree, "real.md") == "foo target")
        let type = try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType
        #expect(type == .typeSymbolicLink)
    }

    @Test
    func filesReachedThroughASymbolicLinkedDirectoryAreSkipped() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        let outside = try WorkspaceSearchEngineTempTree()
        try outside.write("x.md", text: "foo outside")
        try FileManager.default.createSymbolicLink(
            at: tree.root.appendingPathComponent("dir"),
            withDestinationURL: outside.root
        )
        let snapshot = try FileStore().readSnapshot(from: outside.root.appendingPathComponent("x.md"))
        let plan = ReplacementPlan(
            relativePath: "dir/x.md",
            revision: snapshot.revision,
            matches: [SearchMatch(range: NSRange(location: 0, length: 3))],
            replacementText: "bar"
        )

        let outcomes = await WorkspaceReplaceEngine().replace(root: tree.root, plans: [plan])

        #expect(outcomes.first?.outcome == .skippedSymbolicLink)
        #expect(try read(outside, "x.md") == "foo outside")
    }

    @Test
    func protectedPathsAreSkippedWithoutBeingTouched() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("open.md", text: "foo dirty")
        try tree.write("closed.md", text: "foo clean")
        let results = await searchResults(tree, query: "foo")

        let outcomes = await WorkspaceReplaceEngine().replace(
            root: tree.root,
            plans: plans(results, replacement: "bar"),
            isProtected: { $0 == "open.md" }
        )

        let byPath = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.relativePath, $0.outcome) })
        #expect(byPath["open.md"] == .skippedOpenDocumentWithUnsavedChanges)
        #expect(byPath["closed.md"] == .replaced(count: 1))
        #expect(try read(tree, "open.md") == "foo dirty")
    }

    /// Authority review (2026-10-11), F1: the open-document protection was queried once, BEFORE the file was read and
    /// hashed. If the user starts editing that document afterwards, the write must be skipped, not published under
    /// a now-dirty buffer.
    @Test
    func aDocumentThatBecomesDirtyAfterTheFirstProtectionQueryIsNotWritten() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("open.md", text: "foo original")
        let results = await searchResults(tree, query: "foo")
        let planned = plans(results, replacement: "bar")
        let queries = QueryCounter()

        let outcomes = await WorkspaceReplaceEngine().replace(
            root: tree.root,
            plans: planned,
            isProtected: { _ in queries.nextAnswerIsProtected() } // false on the first query, true afterwards
        )

        #expect(outcomes.map(\.outcome) == [.skippedOpenDocumentWithUnsavedChanges])
        #expect(try read(tree, "open.md") == "foo original")
        #expect(queries.count == 2, "protection must be asked again immediately before the write")
    }

    /// #183 F14: the run can be cancelled (root change) while the awaited
    /// protection query is suspended; it must not go on to write.
    @Test
    func cancellationDuringTheProtectionQueryPreventsTheWrite() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "foo a")
        let results = await searchResults(tree, query: "foo")
        let planned = plans(results, replacement: "bar")
        let box = TaskBox()
        let root = tree.root

        let task = Task { @Sendable in
            await WorkspaceReplaceEngine().replace(
                root: root,
                plans: planned,
                isProtected: { _ in
                    box.cancel() // the run is retired while this query is awaiting
                    return false
                }
            )
        }
        box.set(task)
        let outcomes = await task.value

        #expect(outcomes.map(\.outcome) == [.notAttempted])
        #expect(try read(tree, "a.md") == "foo a")
    }

    @Test
    func aDeletedFileIsReportedAndDoesNotStopTheRest() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "foo a")
        try tree.write("b.md", text: "foo b")
        let results = await searchResults(tree, query: "foo")
        try FileManager.default.removeItem(at: tree.root.appendingPathComponent("a.md"))

        let outcomes = await WorkspaceReplaceEngine().replace(
            root: tree.root,
            plans: plans(results, replacement: "bar")
        )

        let byPath = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.relativePath, $0.outcome) })
        #expect(byPath["a.md"] == .skippedUnreadable)
        #expect(byPath["b.md"] == .replaced(count: 1))
        #expect(try read(tree, "b.md") == "bar b")
    }

    @Test
    func invalidPlanRangesNeverProduceOutput() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "foo")
        let snapshot = try FileStore().readSnapshot(from: tree.root.appendingPathComponent("a.md"))
        let bad: [[SearchMatch]] = [
            [SearchMatch(range: NSRange(location: 0, length: 99))],
            [SearchMatch(range: NSRange(location: 2, length: 1)), SearchMatch(range: NSRange(location: 0, length: 1))],
            [SearchMatch(range: NSRange(location: 0, length: 2)), SearchMatch(range: NSRange(location: 1, length: 1))],
            [SearchMatch(range: NSRange(location: NSNotFound, length: 0))],
        ]
        for matches in bad {
            let plan = ReplacementPlan(
                relativePath: "a.md",
                revision: snapshot.revision,
                matches: matches,
                replacementText: "X"
            )
            let outcomes = await WorkspaceReplaceEngine().replace(root: tree.root, plans: [plan])
            #expect(outcomes.first?.outcome == .skippedCannotRepresent)
        }
        #expect(try read(tree, "a.md") == "foo")
    }

    @Test
    func pathsThatEscapeTheRootAreRejected() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        let outside = try WorkspaceSearchEngineTempTree()
        try outside.write("x.md", text: "foo")
        let snapshot = try FileStore().readSnapshot(from: outside.root.appendingPathComponent("x.md"))
        let name = outside.root.lastPathComponent
        for path in ["../\(name)/x.md", "/etc/hosts", "a//b.md", "./x.md", ""] {
            let plan = ReplacementPlan(
                relativePath: path,
                revision: snapshot.revision,
                matches: [SearchMatch(range: NSRange(location: 0, length: 3))],
                replacementText: "bar"
            )
            let outcomes = await WorkspaceReplaceEngine().replace(root: tree.root, plans: [plan])
            guard case .failed = outcomes.first?.outcome else {
                Issue.record("path \(path) was not rejected: \(String(describing: outcomes.first?.outcome))")
                continue
            }
        }
        #expect(try read(outside, "x.md") == "foo")
    }
}

/// Lets a `@Sendable` closure running inside a task cancel that task.
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<[ReplacementFileResult], Never>?
    private var cancelRequested = false

    func set(_ task: Task<[ReplacementFileResult], Never>) {
        lock.lock(); defer { lock.unlock() }
        self.task = task
        if cancelRequested {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelRequested = true
        task?.cancel()
    }
}

private final class QueryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var queries = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return queries
    }

    func nextAnswerIsProtected() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        queries += 1
        return queries > 1
    }
}
