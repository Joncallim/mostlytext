import Foundation
import Testing
@testable import TextSearch

@Suite("WorkspaceSearchEngine index failure")
struct WorkspaceSearchEngineIndexFailureTests {
    @Test func aRebuildAfterSnapshotCaptureCannotTurnAReadySearchIntoAnEmptyCompletion() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "hello")
        let failureFlag = tree.root.appendingPathComponent(".fail")
        let index = WorkspaceFileIndex(walk: { root, excluded in
            if FileManager.default.fileExists(atPath: failureFlag.path) {
                throw CocoaError(.fileReadNoPermission)
            }
            return try DirectoryWalker().walk(root: root, excludedDirectoryNames: excluded)
        })
        await index.rebuild(root: tree.root)
        #expect(await index.state == .ready(count: 1))

        let gate = SnapshotGate()
        let box = WorkspaceSearchEngineResultsBox()
        let engine = WorkspaceSearchEngine(seams: .init(afterIndexSnapshot: { await gate.pause() }))
        let root = tree.root
        let search = Task {
            await engine.search(root: root, index: index, query: "hello", options: SearchOptions()) { match in
                await box.append(match)
            }
        }
        await gate.waitUntilPaused()
        try Data().write(to: failureFlag)
        await index.rebuild(root: tree.root)
        guard case .failed = await index.state else {
            Issue.record("the controlled rebuild must fail while search is paused")
            await gate.resume()
            _ = await search.value
            return
        }
        await gate.resume()

        #expect(await search.value == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        #expect(await box.all.map(\.relativePath) == ["a.txt"])
    }

    /// #183 F18: a failed index (vanished root) is reported as such, not as a
    /// search that merely found nothing.
    @Test func aFailedIndexIsReportedAsUnavailableNotAsNoResults() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "hello")
        let index = await tree.makeIndex()
        try FileManager.default.removeItem(at: tree.root)
        await index.rebuild(root: tree.root)

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "hello")

        #expect(outcome == .indexUnavailable)
        #expect(results.isEmpty)
    }
}

private actor SnapshotGate {
    private var paused = false
    private var released = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        paused = true
        if released {
            return
        }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilPaused() async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while clock.now < deadline {
            if paused {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for the captured index snapshot")
    }

    func resume() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
