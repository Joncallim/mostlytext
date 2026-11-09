import Foundation
import Testing
@testable import TextSearch

/// Review pass 1: a symlinked directory must not hide the real directory (or
/// vice versa) depending on enumeration order, and package directories are not
/// indexed as files.
struct DirectoryWalkerAliasTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func everyAliasOfADirectoryIsIndexedRegardlessOfEnumerationOrder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("v2", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data().write(to: real.appendingPathComponent("page.md"))
        // Names sorting before and after "v2" so both enumeration orders occur.
        for name in ["a", "alias", "latest", "z"] {
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent(name), withDestinationURL: real
            )
        }

        let paths = try Set(DirectoryWalker().walk(root: root, excludedDirectoryNames: []).map(\.relativePath))

        #expect(paths.contains("v2/page.md"))
        for name in ["a", "alias", "latest", "z"] {
            #expect(paths.contains("\(name)/page.md"), "alias \(name) missing")
        }
    }

    @Test func aSymlinkLoopStillTerminates() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data().write(to: sub.appendingPathComponent("f.md"))
        try FileManager.default.createSymbolicLink(
            at: sub.appendingPathComponent("loop"), withDestinationURL: root
        )

        let paths = try DirectoryWalker().walk(root: root, excludedDirectoryNames: []).map(\.relativePath)

        #expect(paths.contains("sub/f.md"))
        #expect(paths.count < 50)
    }

    @Test func packageDirectoriesAreNotIndexedAsFiles() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data().write(to: app.appendingPathComponent("inside.txt"))
        try Data().write(to: root.appendingPathComponent("note.md"))

        let paths = try DirectoryWalker().walk(root: root, excludedDirectoryNames: []).map(\.relativePath)

        #expect(paths == ["note.md"])
    }

    /// `docs -> /` is followed on purpose, so a bound stops the walk instead of indexing a whole disk.
    @Test func theWalkStopsAtTheConfiguredPathLimit() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0 ..< 100 {
            try Data().write(to: root.appendingPathComponent("file\(index).md"))
        }

        let paths = try DirectoryWalker().walk(root: root, excludedDirectoryNames: [], maximumPaths: 10)

        #expect(paths.count == 10)
    }

    @Test func belowTheLimitEverythingIsIndexed() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0 ..< 20 {
            try Data().write(to: root.appendingPathComponent("file\(index).md"))
        }

        #expect(try DirectoryWalker().walk(root: root, excludedDirectoryNames: []).count == 20)
    }

    /// A directory reached through N links is walked N times; a fan-out of links to empty directories adds no paths,
    /// so only a directory budget bounds it (6 links x 6 levels is 46,656 visits and zero files).
    @Test func aSymlinkFanOutOfEmptyDirectoriesStopsAtTheDirectoryBudget() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let levels = 6
        let fanOut = 6
        for level in 0 ..< levels {
            let directory = root.appendingPathComponent("d\(level)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard level + 1 < levels else { continue }
            let next = root.appendingPathComponent("d\(level + 1)", isDirectory: true)
            try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
            for link in 0 ..< fanOut {
                try FileManager.default.createSymbolicLink(
                    at: directory.appendingPathComponent("l\(link)"),
                    withDestinationURL: next
                )
            }
        }
        let start = ContinuousClock.now

        let paths = try DirectoryWalker().walk(root: root, excludedDirectoryNames: [], maximumDirectories: 500)

        #expect(paths.isEmpty)
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
