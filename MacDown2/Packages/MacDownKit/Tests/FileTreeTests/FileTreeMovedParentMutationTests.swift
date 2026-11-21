import Darwin
@testable import FileTree
import Foundation
import Testing

@MainActor
struct FileTreeMovedParentMutationTests {
    private struct Fixture {
        let base: URL
        let root: URL
        let child: URL
        let outside: URL
        let authority: FileTreeMutationAuthority

        func mutator() -> FileSystemMutator {
            FileSystemMutator {
                try FileManager.default.moveItem(at: child, to: outside.appendingPathComponent("dir"))
                try FileManager.default.createSymbolicLink(
                    at: child, withDestinationURL: outside.appendingPathComponent("dir")
                )
            }
        }
    }

    private func fixture() throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("root", isDirectory: true)
        let child = root.appendingPathComponent("dir", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let authority = try FileTreeMutationAuthority(
            lexicalRoot: root, physicalRoot: root,
            identity: #require(FileTreeRootIdentity(url: root))
        )
        return Fixture(base: base, root: root, child: child, outside: outside, authority: authority)
    }

    private func noPrivateStage(in root: URL) throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: root.path)
            .allSatisfy { !$0.hasPrefix(".mostlytext-create-") && !$0.hasPrefix(".mostlytext-copy-") }
    }

    @Test func createFileDoesNotFollowAParentMovedOutsideBeforePublication() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let destination = fixture.child.appendingPathComponent("new.md")
        await #expect(throws: Error.self) {
            try await fixture.mutator().mutate(.createFile(destination), authority: fixture.authority)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.outside.appendingPathComponent("dir/new.md").path))
        #expect(try noPrivateStage(in: fixture.root))
    }

    @Test func createDirectoryDoesNotFollowAParentMovedOutsideBeforePublication() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let destination = fixture.child.appendingPathComponent("new", isDirectory: true)
        await #expect(throws: Error.self) {
            try await fixture.mutator().mutate(.createDirectory(destination), authority: fixture.authority)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.outside.appendingPathComponent("dir/new").path))
        #expect(try noPrivateStage(in: fixture.root))
    }

    @Test func moveDoesNotPublishIntoAParentMovedOutside() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let source = fixture.root.appendingPathComponent("source.md")
        try Data("source".utf8).write(to: source)
        let destination = fixture.child.appendingPathComponent("source.md")
        await #expect(throws: Error.self) {
            try await fixture.mutator().mutate(.move(source, destination), authority: fixture.authority)
        }
        #expect(try Data(contentsOf: source) == Data("source".utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.outside.appendingPathComponent("dir/source.md").path))
    }

    @Test func moveDoesNotRemoveASourceWhoseParentMovedOutside() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let source = fixture.child.appendingPathComponent("source.md")
        try Data("source".utf8).write(to: source)
        let destination = fixture.root.appendingPathComponent("moved.md")
        await #expect(throws: Error.self) {
            try await fixture.mutator().mutate(.move(source, destination), authority: fixture.authority)
        }
        #expect(try Data(contentsOf: fixture.outside.appendingPathComponent("dir/source.md")) == Data("source".utf8))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func copyDoesNotPublishIntoAParentMovedOutside() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let source = fixture.base.appendingPathComponent("source.md")
        try Data("source".utf8).write(to: source)
        let destination = fixture.child.appendingPathComponent("copy.md")
        await #expect(throws: Error.self) {
            try await fixture.mutator().mutate(.copy(source, destination), authority: fixture.authority)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.outside.appendingPathComponent("dir/copy.md").path))
        #expect(try Data(contentsOf: source) == Data("source".utf8))
        #expect(try noPrivateStage(in: fixture.root))
    }
}
