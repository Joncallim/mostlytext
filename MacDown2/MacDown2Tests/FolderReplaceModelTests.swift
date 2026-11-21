import FileCore
import Foundation
@testable import MacDown2
import Testing
import TextSearch

/// EPIC-22 §6.16, Slice 7c — the review/confirm state machine around
/// `WorkspaceReplaceEngine`, exercised against real files through the real
/// engine (the engine's own safety properties are covered in `TextSearchTests`).
@Suite("FolderReplaceModel")
@MainActor
struct FolderReplaceModelTests {
    private final class TempTree {
        let root: URL

        init(_ files: [String: String]) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for (relativePath, text) in files {
                try text.write(to: root.appendingPathComponent(relativePath), atomically: true, encoding: .utf8)
            }
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func read(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
    }

    private func searchedModel(_ tree: TempTree, query: String) async -> FolderSearchModel {
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = FolderSearchModel(index: index, debounce: .zero)
        model.setRoot(tree.root)
        model.query = query
        await waitUntil { model.outcome != nil }
        return model
    }

    @Test func replaceAllRewritesIncludedFilesAndKeepsTheSummaryAfterTheRefreshSearch() async throws {
        let tree = try TempTree(["a.txt": "foo one", "b.txt": "foo two foo", "c.txt": "keep"])
        let model = await searchedModel(tree, query: "foo")
        model.replacement = "bar"
        #expect(model.canReplace)

        model.requestReplace()
        #expect(model.isConfirmingReplace)
        model.confirmReplace()
        #expect(!model.isConfirmingReplace)
        await waitUntil { model.replaceSummary != nil && model.outcome != nil }

        #expect(try tree.read("a.txt") == "bar one")
        #expect(try tree.read("b.txt") == "bar two bar")
        #expect(try tree.read("c.txt") == "keep")
        #expect(model.replaceSummary == FolderReplaceSummary(replacedMatches: 3, replacedFiles: 2, skipped: []))
        #expect(model.results.isEmpty)
        #expect(!model.isReplacing)
    }

    @Test func undecodableFilesAreCountedAsUnsearchedSoReplaceIsNotSilentlyPartial() async throws {
        let tree = try TempTree(["a.txt": "foo a"])
        try Data([0x66, 0x6F, 0x6F, 0xE9]).write(to: tree.root.appendingPathComponent("latin1.txt"))
        let model = await searchedModel(tree, query: "foo")
        #expect(model.results.map(\.relativePath) == ["a.txt"])
        #expect(model.unsearchedFileCount == 1)
    }

    @Test func excludedFilesAreNeverTouched() async throws {
        let tree = try TempTree(["a.txt": "foo a", "b.txt": "foo b"])
        let model = await searchedModel(tree, query: "foo")
        model.setIncluded(false, path: "a.txt")
        model.replacement = "bar"
        #expect(model.includedMatchCount == 1)

        model.requestReplace()
        model.confirmReplace()
        await waitUntil { model.replaceSummary != nil && model.outcome != nil }

        #expect(try tree.read("a.txt") == "foo a")
        #expect(try tree.read("b.txt") == "bar b")
        #expect(model.replaceSummary?.replacedFiles == 1)
    }

    @Test func staleRenderedCheckboxCannotReincludeAChangedMatch() async throws {
        let tree = try TempTree(["a.txt": "foo first"])
        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let model = FolderSearchModel(index: index, debounce: .zero)
        model.setRoot(tree.root)
        model.query = "foo"
        await waitUntil { model.presentedResults.count == 1 && model.outcome != nil }
        let oldRow = try #require(model.presentedResults.first)
        model.setIncluded(false, result: oldRow)

        try "foo changed".write(to: tree.root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        await index.rebuild(root: tree.root)
        model.indexDidRefresh(root: tree.root)
        await waitUntil { model.presentedResults.count == 1 && model.outcome != nil }
        let currentRow = try #require(model.presentedResults.first)
        #expect(!model.isCurrentResult(oldRow))
        #expect(model.isCurrentResult(currentRow))
        #expect(model.excludedPaths.contains("a.txt"))

        model.setIncluded(true, result: oldRow)
        model.togglePreview(result: oldRow)
        #expect(model.excludedPaths.contains("a.txt"))
        #expect(!model.expandedPaths.contains("a.txt"))

        model.setIncluded(true, result: currentRow)
        #expect(!model.excludedPaths.contains("a.txt"))
    }

    /// Review pass 6: a rewritten file gets a new inode and creation date, so its Open Recent entry was rejected by
    /// the fingerprint check and silently dropped on the next click.
    @Test func everyRewrittenFileIsReportedSoRecentsCanFollowIt() async throws {
        let tree = try TempTree(["a.txt": "foo a", "b.txt": "foo b", "c.txt": "none"])
        let model = await searchedModel(tree, query: "foo")
        var rewritten: [String] = []
        model.fileWasRewritten = { rewritten.append($0.lastPathComponent) }
        model.replacement = "bar"

        model.requestReplace()
        model.confirmReplace()
        await waitUntil { model.replaceSummary != nil && model.outcome != nil }

        #expect(rewritten.sorted() == ["a.txt", "b.txt"])
    }

    @Test func aFileOpenWithUnsavedChangesIsSkippedAndReported() async throws {
        let tree = try TempTree(["dirty.txt": "foo dirty", "clean.txt": "foo clean"])
        let model = await searchedModel(tree, query: "foo")
        model.hasUnsavedOpenDocument = { $0.lastPathComponent == "dirty.txt" }
        model.replacement = "bar"

        model.requestReplace()
        model.confirmReplace()
        await waitUntil { model.replaceSummary != nil && model.outcome != nil }

        #expect(try tree.read("dirty.txt") == "foo dirty")
        #expect(try tree.read("clean.txt") == "bar clean")
        #expect(model.replaceSummary?.skipped == [
            ReplacementFileResult(relativePath: "dirty.txt", outcome: .skippedOpenDocumentWithUnsavedChanges),
        ])
    }

    @Test func replaceIsUnavailableForTruncatedOrIncompleteResults() async {
        let runs = ReplaceRunCounter()
        let model = FolderSearchModel(
            performSearch: { _, _, onMatch in
                await onMatch(FolderSearchMatch(
                    relativePath: "a.txt",
                    matches: [SearchMatch(range: NSRange(location: 0, length: 1))],
                    revision: Self.dummyRevision
                ))
                return .truncated(filesSearched: 1, filesSkipped: 0, matchCount: 1)
            },
            performReplace: { _, _, _, _, _ in
                await runs.increment()
                return []
            }
        )
        model.setRoot(URL(fileURLWithPath: "/tmp/never-touched"))
        model.query = "x"
        await waitUntil { model.outcome != nil }

        #expect(!model.canReplace)
        model.requestReplace()
        #expect(!model.isConfirmingReplace)
        model.confirmReplace()
        #expect(!model.isReplacing)
        #expect(await runs.value == 0)
    }

    @Test func editingTheQueryDismissesAPendingConfirmationAndClearsExclusions() async throws {
        let tree = try TempTree(["a.txt": "foo a", "b.txt": "foo b"])
        let model = await searchedModel(tree, query: "foo")
        model.setIncluded(false, path: "a.txt")
        model.requestReplace()
        #expect(model.isConfirmingReplace)

        model.query = "fo"

        #expect(!model.isConfirmingReplace)
        #expect(model.excludedPaths.isEmpty)
        #expect(model.replaceSummary == nil)
    }

    @Test func aPreviewLoadsWhenExpandedAndFollowsTheReplacementText() async throws {
        let tree = try TempTree(["a.txt": "one foo two"])
        let model = await searchedModel(tree, query: "foo")
        model.replacement = "bar"

        model.togglePreview(path: "a.txt")
        await waitUntil { model.previews["a.txt"] != nil }
        #expect(model.previews["a.txt"] == .lines(
            [ReplacementPreviewLine(lineNumber: 1, before: "one foo two", after: "one bar two")],
            totalRegionCount: 1
        ))

        model.replacement = "baz"
        #expect(model.previews["a.txt"] == nil)
        await waitUntil { model.previews["a.txt"] != nil }
        #expect(model.previews["a.txt"] == .lines(
            [ReplacementPreviewLine(lineNumber: 1, before: "one foo two", after: "one baz two")],
            totalRegionCount: 1
        ))

        model.togglePreview(path: "a.txt")
        #expect(!model.expandedPaths.contains("a.txt"))
        #expect(try tree.read("a.txt") == "one foo two")
    }

    @Test func changingTheRootCancelsARunningReplaceAndDiscardsItsLateSummary() async throws {
        let gate = ReplaceGate()
        let oldTree = try TempTree(["a.txt": "x"])
        let newTree = try TempTree(["a.txt": "x"])
        let model = FolderSearchModel(
            performSearch: { _, _, onMatch in
                await onMatch(FolderSearchMatch(
                    relativePath: "a.txt",
                    matches: [SearchMatch(range: NSRange(location: 0, length: 1))],
                    revision: Self.dummyRevision
                ))
                return .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1)
            },
            performReplace: { _, _, plans, _, _ in
                await gate.enterAndWait()
                return plans.map { ReplacementFileResult(relativePath: $0.relativePath, outcome: .replaced(count: 1)) }
            }
        )
        model.setRoot(oldTree.root)
        model.query = "x"
        await waitUntil { model.outcome != nil }
        model.requestReplace()
        model.confirmReplace()
        await gate.waitUntilEntered()
        #expect(model.isReplacing)

        model.setRoot(newTree.root)
        await gate.release()
        try await Task.sleep(for: .milliseconds(100))

        #expect(!model.isReplacing)
        #expect(model.replaceSummary == nil)
        #expect(model.replaceTask == nil)
    }

    @Test func settingTheSameRootAgainDoesNotRetireARunningReplace() async throws {
        let gate = ReplaceGate()
        let tree = try TempTree(["a.txt": "x"])
        let model = FolderSearchModel(
            performSearch: { _, _, onMatch in
                await onMatch(FolderSearchMatch(
                    relativePath: "a.txt",
                    matches: [SearchMatch(range: NSRange(location: 0, length: 1))],
                    revision: Self.dummyRevision
                ))
                return .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1)
            },
            performReplace: { _, _, plans, _, _ in
                await gate.enterAndWait()
                return plans.map { ReplacementFileResult(relativePath: $0.relativePath, outcome: .replaced(count: 1)) }
            }
        )
        model.setRoot(tree.root)
        model.query = "x"
        await waitUntil { model.outcome != nil }
        model.requestReplace()
        model.confirmReplace()
        await gate.waitUntilEntered()

        model.setRoot(tree.root)
        #expect(model.isReplacing)
        await gate.release()
        await waitUntil { model.replaceSummary != nil }

        #expect(model.replaceSummary?.replacedFiles == 1)
    }

    @Test func summaryCountsReplacedAndSkippedResults() {
        let summary = FolderSearchModel.summarize([
            ReplacementFileResult(relativePath: "a", outcome: .replaced(count: 2)),
            ReplacementFileResult(relativePath: "b", outcome: .skippedChangedSinceSearch),
            ReplacementFileResult(relativePath: "c", outcome: .notAttempted),
            ReplacementFileResult(relativePath: "d", outcome: .replaced(count: 1)),
        ])
        #expect(summary.replacedMatches == 3)
        #expect(summary.replacedFiles == 2)
        #expect(summary.skipped.map(\.relativePath) == ["b", "c"])
    }

    private static let dummyRevision = FileRevision(
        url: URL(fileURLWithPath: "/tmp/a.txt"),
        modificationDate: nil,
        fileSize: 0,
        fileObjectID: nil,
        sha256: ""
    )
}

private actor ReplaceGate {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func enterAndWait() async {
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async {
        while !entered {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor ReplaceRunCounter {
    private(set) var value = 0
    func increment() {
        value += 1
    }
}

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
    Issue.record("Timed out waiting for FolderSearchModel replace state to settle")
}
