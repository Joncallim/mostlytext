import Foundation
import Testing
@testable import TextSearch

@Suite("Workspace index enumeration failures")
struct WorkspaceIndexEnumerationFailureTests {
    @Test func pathBudgetCannotPublishAPartialReadyIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("first.md"))
        try Data().write(to: root.appendingPathComponent("second.md"))
        let index = WorkspaceFileIndex(walk: { root, excluded in
            try DirectoryWalker().walk(root: root, excludedDirectoryNames: excluded, maximumPaths: 2)
        })

        await index.rebuild(root: root)
        #expect(await index.state == .ready(count: 2))
        try Data().write(to: root.appendingPathComponent("third.md"))
        await index.rebuild(root: root)

        guard case .failed = await index.state else {
            Issue.record("a capped path scan must not publish its earlier paths as ready")
            return
        }
        #expect(await index.allPaths().isEmpty)
        #expect(await index.query("first").isEmpty)

        try FileManager.default.removeItem(at: root.appendingPathComponent("third.md"))
        await index.rebuild(root: root)
        #expect(await index.state == .ready(count: 2))
    }

    @Test func directoryBudgetCannotPublishAPartialReadyIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("first.md"))
        let index = WorkspaceFileIndex(walk: { root, excluded in
            try DirectoryWalker().walk(root: root, excludedDirectoryNames: excluded, maximumDirectories: 1)
        })

        await index.rebuild(root: root)
        #expect(await index.state == .ready(count: 1))
        let child = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data().write(to: child.appendingPathComponent("second.md"))
        await index.rebuild(root: root)

        guard case .failed = await index.state else {
            Issue.record("a capped directory scan must not publish its earlier paths as ready")
            return
        }
        #expect(await index.allPaths().isEmpty)
        #expect(await index.query("first").isEmpty)

        try FileManager.default.removeItem(at: child)
        await index.rebuild(root: root)
        #expect(await index.state == .ready(count: 1))
    }

    @Test func unreadableSymlinkTargetCannotHideItsSubtreeInAReadyIndex() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("workspace", isDirectory: true)
        let target = parent.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("first.md"))
        try Data().write(to: target.appendingPathComponent("linked.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: target)
        let trigger = parent.appendingPathComponent("fail.flag")
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey]

        let index = WorkspaceFileIndex(walk: { root, excluded in
            try DirectoryWalker(listChildren: { directory in
                try FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: Array(keys), options: []
                ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            }, readValues: { entry in
                if entry == target, FileManager.default.fileExists(atPath: trigger.path) {
                    throw CocoaError(.fileReadNoPermission)
                }
                return try entry.resourceValues(forKeys: keys)
            }).walk(root: root, excludedDirectoryNames: excluded)
        })

        await index.rebuild(root: root)
        #expect(await index.state == .ready(count: 2))
        #expect(await index.query("linked").map(\.relativePath) == ["link/linked.md"])

        try Data().write(to: trigger)
        await index.rebuild(root: root)

        guard case .failed = await index.state else {
            Issue.record("a failed symlink-target read must not hide its subtree in a ready index")
            return
        }
        #expect(await index.allPaths().isEmpty)
        #expect(await index.query("first").isEmpty)
    }

    @Test func unreadableChildMetadataCannotPublishAPartialIndex() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("first.md"))
        try Data().write(to: root.appendingPathComponent("later.md"))
        let trigger = parent.appendingPathComponent("fail.flag")
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey]

        let index = WorkspaceFileIndex(walk: { root, excluded in
            try DirectoryWalker(listChildren: { directory in
                try FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: Array(keys), options: []
                ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            }, readValues: { entry in
                if entry.lastPathComponent == "later.md", FileManager.default.fileExists(atPath: trigger.path) {
                    throw CocoaError(.fileReadNoPermission)
                }
                return try entry.resourceValues(forKeys: keys)
            }).walk(root: root, excludedDirectoryNames: excluded)
        })

        await index.rebuild(root: root)
        #expect(await index.state == .ready(count: 2))
        #expect(await index.query("first").map(\.relativePath) == ["first.md"])

        try Data().write(to: trigger)
        await index.rebuild(root: root)

        guard case .failed = await index.state else {
            Issue.record("an unreadable entry's metadata must not produce a partial ready index")
            return
        }
        #expect(await index.allPaths().isEmpty)
        #expect(await index.query("first").isEmpty)
    }

    @Test func missingChildClassificationCannotProduceAReadyIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("page.md")
        try Data().write(to: file)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey]
        let index = WorkspaceFileIndex(walk: { root, excluded in
            try DirectoryWalker(listChildren: { directory in
                try FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: Array(keys), options: []
                )
            }, readValues: { entry in
                entry.lastPathComponent == file.lastPathComponent
                    ? URLResourceValues() : try entry.resourceValues(forKeys: keys)
            }).walk(root: root, excludedDirectoryNames: excluded)
        })

        await index.rebuild(root: root)
        guard case .failed = await index.state else {
            Issue.record("missing required metadata must fail rather than classify a file by default")
            return
        }
        #expect(await index.allPaths().isEmpty)
    }

    @Test func missingSymlinkTargetClassificationCannotProduceAReadyIndex() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("workspace", isDirectory: true)
        let target = parent.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data().write(to: target.appendingPathComponent("page.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: target)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey]
        let index = WorkspaceFileIndex(walk: { root, excluded in
            try DirectoryWalker(listChildren: { directory in
                try FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: Array(keys), options: []
                )
            }, readValues: { entry in
                entry.path == target.path ? URLResourceValues() : try entry.resourceValues(forKeys: keys)
            }).walk(root: root, excludedDirectoryNames: excluded)
        })

        await index.rebuild(root: root)
        guard case .failed = await index.state else {
            Issue.record("missing target metadata must fail rather than hide a linked subtree")
            return
        }
        #expect(await index.allPaths().isEmpty)
    }

    @Test func unreadableChildCannotPublishAPartialIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("keep.md"))
        try Data().write(to: child.appendingPathComponent("hidden-by-failure.md"))
        let trigger = root.appendingPathComponent("fail.flag")

        let index = WorkspaceFileIndex(walk: { root, excluded in
            try DirectoryWalker(listChildren: { directory in
                if directory == child, FileManager.default.fileExists(atPath: trigger.path) {
                    throw CocoaError(.fileReadNoPermission)
                }
                return try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey],
                    options: []
                )
            }).walk(root: root, excludedDirectoryNames: excluded)
        })

        await index.rebuild(root: root)
        #expect(await index.state == .ready(count: 2))
        #expect(await index.query("keep").map(\.relativePath) == ["keep.md"])

        try Data().write(to: trigger)
        await index.rebuild(root: root)

        guard case .failed = await index.state else {
            Issue.record("a child enumeration failure must not look like a complete index")
            return
        }
        #expect(await index.allPaths().isEmpty)
        #expect(await index.query("keep").isEmpty)
    }

    @Test func supersededReadFailureCannotEraseANewerIndex() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let firstRoot = parent.appendingPathComponent("first", isDirectory: true)
        let secondRoot = parent.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        let gate = FailureGate()
        let index = WorkspaceFileIndex(walk: { root, _ in
            if root == firstRoot {
                gate.blockUntilReleased()
                throw CocoaError(.fileReadNoPermission)
            }
            return [IndexedPath(relativePath: "new.md", basename: "new.md")]
        })

        let first = Task { await index.rebuild(root: firstRoot) }
        let blocked = gate.waitUntilBlocked()
        await index.rebuild(root: secondRoot)
        gate.release()
        await first.value

        #expect(blocked)
        #expect(await index.state == .ready(count: 1))
        #expect(await index.query("").map(\.relativePath) == ["new.md"])
    }
}

private final class FailureGate: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    func blockUntilReleased() {
        started.signal()
        released.wait()
    }

    func waitUntilBlocked() -> Bool {
        started.wait(timeout: .now() + 5) == .success
    }

    func release() {
        released.signal()
    }
}
