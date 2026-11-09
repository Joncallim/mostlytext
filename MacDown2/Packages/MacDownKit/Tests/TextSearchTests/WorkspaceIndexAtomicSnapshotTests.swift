import Foundation
import Testing
@testable import TextSearch

@Suite("Workspace index atomic snapshots")
struct WorkspaceIndexAtomicSnapshotTests {
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
