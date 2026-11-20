@testable import FileTree
import Foundation
import Testing

/// #183 F14: a symlinked directory inside the root may be navigated, but every
/// mutation below it would land outside the approved tree and must be refused.
@MainActor
struct FileTreeSymlinkMutationAuthorityTests {
    private struct Fixture {
        let base: URL
        let root: URL
        let outside: URL
        let link: URL
        let outsideFile: URL
        let insideFile: URL
    }

    private func makeFixture() throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("root", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile = outside.appendingPathComponent("secret.md")
        let insideFile = root.appendingPathComponent("note.md")
        try Data("secret".utf8).write(to: outsideFile)
        try Data("note".utf8).write(to: insideFile)
        let link = root.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        return Fixture(
            base: base, root: root, outside: outside, link: link,
            outsideFile: outsideFile, insideFile: insideFile
        )
    }

    private func model(rootedAt root: URL) async -> FileTreeModel {
        let model = FileTreeModel(
            watcher: TestWatching(),
            preferences: FileTreePreferences(store: MemoryPreferenceStore()),
            supportedExtensions: ["md"]
        )
        await model.setRoot(root)
        return model
    }

    @Test func mutationsThroughASymlinkedDirectoryAreRefusedAndTouchNothingOutside() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let model = await model(rootedAt: fixture.root)
        let throughLink = fixture.link.appendingPathComponent("secret.md")

        await #expect(throws: FileTreeOperationError.outsideCurrentRoot) {
            try await model.createFile(in: fixture.link)
        }
        await #expect(throws: FileTreeOperationError.outsideCurrentRoot) {
            try await model.createFolder(in: fixture.link)
        }
        await #expect(throws: FileTreeOperationError.outsideCurrentRoot) {
            try await model.rename(throughLink, to: "renamed.md")
        }
        await #expect(throws: FileTreeOperationError.outsideCurrentRoot) {
            try await model.duplicate(throughLink)
        }
        await #expect(throws: FileTreeOperationError.outsideCurrentRoot) {
            try await model.moveToTrash(throughLink)
        }
        await #expect(throws: FileTreeOperationError.outsideCurrentRoot) {
            try await model.move(fixture.insideFile, intoDirectory: fixture.link)
        }
        await #expect(throws: FileTreeOperationError.outsideCurrentRoot) {
            try await model.copyExternal(fixture.insideFile, intoDirectory: fixture.link)
        }

        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.outside.path)
        #expect(names == ["secret.md"])
        #expect(try Data(contentsOf: fixture.outsideFile) == Data("secret".utf8))
        #expect(FileManager.default.fileExists(atPath: fixture.insideFile.path))
    }

    @Test func theLinkItselfCanStillBeRenamedAndOrdinaryEditsStillWork() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let model = await model(rootedAt: fixture.root)

        let renamed = try await model.rename(fixture.link, to: "alias")
        #expect(renamed.url.lastPathComponent == "alias")
        #expect(FileManager.default.fileExists(atPath: fixture.outsideFile.path))

        let created = try await model.createFile(in: fixture.root)
        #expect(FileManager.default.fileExists(atPath: created.url.path))
    }

    @Test func retargetingTheSelectedRootAliasCannotAuthorizeWritesToItsNewTarget() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let alias = fixture.base.appendingPathComponent("selected-root", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.root)
        let model = await model(rootedAt: alias)

        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.outside)

        await #expect(throws: FileTreeOperationError.outsideCurrentRoot) {
            try await model.createFile(in: alias)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.outside.path) == ["secret.md"])
    }

    @Test func replacingTheSelectedRootAtTheSamePathCannotAuthorizeWritesToTheReplacement() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let model = await model(rootedAt: fixture.root)
        let original = fixture.base.appendingPathComponent("original", isDirectory: true)
        try FileManager.default.moveItem(at: fixture.root, to: original)
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: false)

        await #expect(throws: FileTreeOperationError.outsideCurrentRoot) {
            try await model.createFile(in: fixture.root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }
}
