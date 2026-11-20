import Darwin
@testable import FileTree
import Foundation
import Testing

@MainActor
struct FileTreeRootedCopyTests {
    @Test func externalDirectoryCopyKeepsNestedBytesModesAndSymlinks() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        let destination = base.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        #expect(Darwin.chmod(source.path, 0o750) == 0)
        let file = nested.appendingPathComponent("note.md")
        try Data("authored\n".utf8).write(to: file)
        #expect(Darwin.chmod(file.path, 0o640) == 0)
        let link = source.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        let model = FileTreeModel(
            watcher: TestWatching(),
            preferences: FileTreePreferences(store: MemoryPreferenceStore()),
            supportedExtensions: ["md"]
        )
        await model.setRoot(destination)
        let result = try await model.copyExternal(source, intoDirectory: destination)
        let copiedFile = result.url.appendingPathComponent("nested/note.md")
        let copiedLink = result.url.appendingPathComponent("alias")
        #expect(try Data(contentsOf: copiedFile) == Data("authored\n".utf8))
        var sourceInfo = stat()
        var copyInfo = stat()
        #expect(Darwin.lstat(file.path, &sourceInfo) == 0)
        #expect(Darwin.lstat(copiedFile.path, &copyInfo) == 0)
        #expect(sourceInfo.st_mode & 0o777 == copyInfo.st_mode & 0o777)
        #expect(Darwin.lstat(source.path, &sourceInfo) == 0)
        #expect(Darwin.lstat(result.url.path, &copyInfo) == 0)
        #expect(sourceInfo.st_mode & 0o777 == copyInfo.st_mode & 0o777)
        #expect(Darwin.lstat(copiedLink.path, &copyInfo) == 0)
        #expect(copyInfo.st_mode & S_IFMT == S_IFLNK)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: copiedLink.path) == file.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path) == ["source"])
    }

    @Test func lateDestinationCollisionCannotReplaceTheOtherWritersBytes() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source.md")
        let rootURL = base.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source)
        let destination = rootURL.appendingPathComponent("source.md")
        try Data("other writer".utf8).write(to: destination)
        let authority = try FileTreeMutationAuthority(
            lexicalRoot: rootURL, physicalRoot: rootURL,
            identity: #require(FileTreeRootIdentity(url: rootURL))
        )
        let root = try FileTreeRootedDirectory(authority)

        #expect(throws: POSIXError.self) {
            try FileTreeRootedCopy.copy(source, to: destination, root: root)
        }
        #expect(try Data(contentsOf: destination) == Data("other writer".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: rootURL.path) == ["source.md"])
    }

    @Test func failedDirectoryCopyRemovesItsPrivateStage() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source", isDirectory: true)
        let rootURL = base.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        #expect(Darwin.mkfifo(source.appendingPathComponent("pipe").path, 0o600) == 0)
        let model = FileTreeModel(
            watcher: TestWatching(),
            preferences: FileTreePreferences(store: MemoryPreferenceStore()),
            supportedExtensions: ["md"]
        )
        await model.setRoot(rootURL)

        await #expect(throws: FileTreeOperationError.self) {
            try await model.copyExternal(source, intoDirectory: rootURL)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: rootURL.path).isEmpty)
    }

    @Test func collisionAfterReadOnlyDirectoryCopyRemovesItsPrivateStage() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = base.appendingPathComponent("source", isDirectory: true)
        defer {
            _ = Darwin.chmod(source.path, 0o700)
            try? FileManager.default.removeItem(at: base)
        }
        let rootURL = base.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("authored".utf8).write(to: source.appendingPathComponent("note.md"))
        #expect(Darwin.chmod(source.path, 0o500) == 0)
        let destination = rootURL.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let authority = try FileTreeMutationAuthority(
            lexicalRoot: rootURL, physicalRoot: rootURL,
            identity: #require(FileTreeRootIdentity(url: rootURL))
        )
        let root = try FileTreeRootedDirectory(authority)

        #expect(throws: POSIXError.self) {
            try FileTreeRootedCopy.copy(source, to: destination, root: root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: rootURL.path) == ["source"])
    }
}
