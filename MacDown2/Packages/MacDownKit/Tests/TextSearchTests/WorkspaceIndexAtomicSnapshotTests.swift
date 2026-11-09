import Foundation
import Testing
@testable import TextSearch

@Suite("Workspace index atomic snapshots")
struct WorkspaceIndexAtomicSnapshotTests {
    @Test func displayedPathIsRevokedByFailureAndSamePathRebuild() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("same.md"))
        let failureFlag = root.appendingPathComponent(".fail")
        let index = WorkspaceFileIndex(walk: { root, excluded in
            if FileManager.default.fileExists(atPath: failureFlag.path) {
                throw CocoaError(.fileReadNoPermission)
            }
            return try DirectoryWalker().walk(root: root, excludedDirectoryNames: excluded)
        })

        await index.rebuild(root: root)
        let first = await index.querySnapshot("same")
        let row = try #require(first.paths.first)
        #expect(await index.isActionable(row, publishedGeneration: first.publishedGeneration))
        let unlisted = IndexedPath(relativePath: "other.md", basename: "other.md")
        #expect(await !(index.isActionable(unlisted, publishedGeneration: first.publishedGeneration)))
        let mismatched = IndexedPath(relativePath: "same.md", basename: "other.md")
        #expect(await !(index.isActionable(mismatched, publishedGeneration: first.publishedGeneration)))

        try Data().write(to: failureFlag)
        await index.rebuild(root: root)
        #expect(await !(index.isActionable(row, publishedGeneration: first.publishedGeneration)))
        try FileManager.default.removeItem(at: failureFlag)
        await index.rebuild(root: root)
        let second = await index.querySnapshot("same")
        #expect(second.paths.first?.relativePath == row.relativePath)
        #expect(second.publishedGeneration != first.publishedGeneration)
        #expect(await !(index.isActionable(row, publishedGeneration: first.publishedGeneration)))
        #expect(await index.isActionable(row, publishedGeneration: second.publishedGeneration))

        await index.clear()
        #expect(await !(index.isActionable(row, publishedGeneration: second.publishedGeneration)))
    }

    @Test func separateReadsCanCrossAFailedRebuildButSnapshotsStayCoherent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("first.md"))
        let failureFlag = root.appendingPathComponent(".fail")
        let index = WorkspaceFileIndex(walk: { root, excluded in
            if FileManager.default.fileExists(atPath: failureFlag.path) {
                throw CocoaError(.fileReadNoPermission)
            }
            return try DirectoryWalker().walk(root: root, excludedDirectoryNames: excluded)
        })

        await index.rebuild(root: root)
        let earlyState = await index.state
        #expect(earlyState == .ready(count: 1))
        try Data().write(to: failureFlag)
        await index.rebuild(root: root)
        let latePaths = await index.allPaths()
        #expect(latePaths.isEmpty) // The old two-await folder search could pair this with `earlyState`.

        let folderSnapshot = await index.allPathsSnapshot()
        guard case .failed = folderSnapshot.state else {
            Issue.record("the folder snapshot must carry the failed state")
            return
        }
        #expect(folderSnapshot.paths.isEmpty)

        try FileManager.default.removeItem(at: failureFlag)
        await index.rebuild(root: root)
        let earlyQuery = await index.query("first")
        #expect(earlyQuery.map(\.relativePath) == ["first.md"])
        try Data().write(to: failureFlag)
        await index.rebuild(root: root)
        guard case .failed = await index.state else {
            Issue.record("the second rebuild must fail")
            return
        }
        // The old two-await Quick Open read could pair `earlyQuery` with
        // that later failure. The one-call result cannot mix generations.
        let quickOpenSnapshot = await index.querySnapshot("first")
        guard case .failed = quickOpenSnapshot.state else {
            Issue.record("the Quick Open snapshot must carry the failed state")
            return
        }
        #expect(quickOpenSnapshot.paths.isEmpty)
    }
}
