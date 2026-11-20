import Foundation
import Testing
@testable import TextSearch

@Suite("Folder regex deadline")
struct WorkspaceRegexDeadlineTests {
    @Test func wholeFolderBudgetReportsTimeoutBeforePublishingAnIncompleteSearch() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "needle")
        let index = await tree.makeIndex()
        let engine = WorkspaceSearchEngine(seams: .init(regexSearchBudget: .zero))

        let outcome = await engine.search(
            root: tree.root, index: index, query: "needle", options: SearchOptions(isRegex: true)
        ) { _ in Issue.record("expired search must not publish a row") }

        #expect(outcome == .timedOut(filesSearched: 0, filesSkipped: 0, matchCount: 0))
    }

    @Test func aPathologicalFileReportsIncompleteResultsAfterEarlierStreamedMatches() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "needle")
        try tree.write("b.txt", text: String(repeating: "x", count: 40) + "!")
        let index = WorkspaceFileIndex()
        await index.seedForTesting([
            IndexedPath(relativePath: "a.txt", basename: "a.txt"),
            IndexedPath(relativePath: "b.txt", basename: "b.txt"),
        ])

        let start = ContinuousClock.now
        let (outcome, results) = await runFolderSearch(
            root: tree.root, index: index, query: "needle|(x+x+)+y", options: SearchOptions(isRegex: true)
        )

        #expect(outcome == .timedOut(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        #expect(results.map(\.relativePath) == ["a.txt"])
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
