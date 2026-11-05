import Foundation
import LocalResourceAccess
@testable import MacDown2
import Testing

@Suite("Preview directory grant lifetime")
@MainActor
struct PreviewDirectoryGrantBackingTests {
    @Test func revokedGrantKeepsAdmittedDirectoryAliveUntilWorkerUseEnds() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("chosen", isDirectory: true)
        let documentDirectory = root.appendingPathComponent("article", isDirectory: true)
        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        let document = documentDirectory.appendingPathComponent("story.md")
        let image = documentDirectory.appendingPathComponent("image.png")
        try Data("original".utf8).write(to: image)

        let selection = try #require(PreviewResourceFolderSelection.fixture(documentURL: document, folderURL: root))
        let grant = try await PreviewDirectoryGrantBacking.acquire(
            selection: selection, currentDocumentURL: document, epoch: UUID()
        )
        var use = grant.acquireUse()
        try #require(use != nil)
        let pinnedDirectory = try #require(use?.documentDirectory)
        grant.revoke()
        #expect(grant.acquireUse() == nil)
        let reference = try ResourceReference.parse("image.png")
        let original = try ContainedResourceReader.read(reference, in: pinnedDirectory, maxBytes: 100)
        #expect(original.bytes == Data("original".utf8))

        use = nil
        #expect(throws: ResourceReadError.leaseClosed) {
            try ContainedResourceReader.read(reference, in: pinnedDirectory, maxBytes: 100)
        }
    }

    @Test func replacementAtSelectedNameCannotBecomeTheGrant() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("chosen", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let document = root.appendingPathComponent("story.md")
        let selection = try #require(PreviewResourceFolderSelection.fixture(documentURL: document, folderURL: root))

        try FileManager.default.moveItem(at: root, to: sandbox.appendingPathComponent("original"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await #expect(throws: ResourceReadError.changedRoot) {
            try await PreviewDirectoryGrantBacking.acquire(
                selection: selection, currentDocumentURL: document, epoch: UUID()
            )
        }
    }

    @Test func selectedFolderCannotGrantASeparateDocumentDirectory() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("chosen", isDirectory: true)
        let other = sandbox.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let document = other.appendingPathComponent("story.md")
        let selection = try #require(PreviewResourceFolderSelection.fixture(documentURL: document, folderURL: root))

        await #expect(throws: ResourceReadError.denied) {
            try await PreviewDirectoryGrantBacking.acquire(
                selection: selection, currentDocumentURL: document, epoch: UUID()
            )
        }
    }

    private func makeSandbox() throws -> URL {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        return sandbox
    }
}
