import Foundation
import LocalResourceAccess
@testable import MacDown2
import Testing

@Suite("Preview directory grant lifetime")
@MainActor
struct PreviewDirectoryGrantBackingTests {
    @Test func automaticScopeStopsOnlyAfterTheLastAdmittedUse() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let document = sandbox.appendingPathComponent("story.html")
        let counter = PreviewScopeCounter()
        let grant = try PreviewDirectoryGrantBacking.acquireAutomatic(
            documentURL: document, epoch: UUID(), scopeAccess: counter.access
        )
        #expect(counter.started == [sandbox])
        var use = grant.acquireUse()
        #expect(use != nil)
        grant.revoke()
        #expect(counter.stopped.isEmpty)
        use = nil
        try await counter.waitForStops(1)
        #expect(counter.stopped == [sandbox])
        grant.revoke()
        #expect(counter.stopped.count == 1)
    }

    @Test func failedAutomaticDirectoryOpenStopsItsStartedScope() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let counter = PreviewScopeCounter()
        #expect(throws: (any Error).self) {
            try PreviewDirectoryGrantBacking.acquireAutomatic(
                documentURL: sandbox.appendingPathComponent("story.html"),
                epoch: UUID(), scopeAccess: counter.access
            )
        }
        #expect(counter.started == [sandbox])
        #expect(counter.stopped == [sandbox])
    }

    @Test func automaticDocumentDirectoryDrainsAnAdmittedUseAfterRevocation() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let document = sandbox.appendingPathComponent("story.html")
        try Data("nearby".utf8).write(to: sandbox.appendingPathComponent("asset.txt"))
        let grant = try PreviewDirectoryGrantBacking.acquireAutomatic(documentURL: document, epoch: UUID())
        #expect(grant.requestedDocumentURL == document)

        var use = grant.acquireUse()
        let directory = try #require(use?.documentDirectory)
        grant.revoke()
        #expect(grant.acquireUse() == nil)
        let reference = try ResourceReference.parse("asset.txt")
        #expect(try ContainedResourceReader.read(reference, in: directory, maxBytes: 100).bytes
            == Data("nearby".utf8))

        use = nil
        #expect(throws: ResourceReadError.leaseClosed) {
            try ContainedResourceReader.read(reference, in: directory, maxBytes: 100)
        }
    }

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

@MainActor
final class PreviewScopeCounter {
    private(set) var started: [URL] = []
    private(set) var stopped: [URL] = []

    var access: PreviewDirectoryScopeAccess {
        PreviewDirectoryScopeAccess(
            start: { [self] url in
                started.append(url)
                return true
            },
            stop: { [self] url in stopped.append(url) }
        )
    }

    func waitForStops(_ expected: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while stopped.count < expected, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(stopped.count == expected)
    }
}
