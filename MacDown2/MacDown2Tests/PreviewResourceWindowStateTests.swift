import FileCore
import Foundation
@testable import MacDown2
import Testing

@Suite("Preview window resource ownership")
@MainActor
struct PreviewResourceWindowStateTests {
    @Test func closingWindowRevokesBothConsumersAndItsBacking() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"))
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let owner = PreviewResourceWindowState()
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: origin) { document }
        let markdown = try #require(owner.beginLoad(for: document, consumer: .markdown))
        let html = try #require(owner.beginLoad(for: document, consumer: .html))
        #expect(markdown.id != html.id)

        owner.close()
        #expect(markdown.isRevoked)
        #expect(html.isRevoked)
        #expect(markdown.acquireUse() == nil)
        #expect(html.acquireUse() == nil)
        #expect(owner.beginLoad(for: document, consumer: .markdown) == nil)
    }

    @Test func switchedDocumentRejectsAnAwaitingFolderSelection() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"))
        let other = FileDocument(fileURL: folder.appendingPathComponent("other.md"))
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let owner = PreviewResourceWindowState()
        let origin = try #require(owner.beginSelection(for: document))
        var reads = 0
        await #expect(throws: PreviewResourceAdmissionError.revoked) {
            try await owner.install(selection, from: origin) {
                reads += 1
                return reads == 1 ? document : other
            }
        }
        #expect(owner.beginLoad(for: document, consumer: .markdown) == nil)
    }

    @Test func observedAwayAndBackCannotReusePendingSelection() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"))
        let other = FileDocument(fileURL: folder.appendingPathComponent("other.md"))
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let owner = PreviewResourceWindowState()
        let origin = try #require(owner.beginSelection(for: document))
        owner.reconcile(with: other)
        owner.reconcile(with: document)
        await #expect(throws: PreviewResourceAdmissionError.revoked) {
            try await owner.install(selection, from: origin) { document }
        }
    }

    @Test func delayedOldMarkdownTaskCannotRetireTheNewGeneration() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"))
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let owner = PreviewResourceWindowState()
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: origin) { document }
        let tabID = UUID()
        var liveDocument = document
        owner.setCurrentPreviewDocument { (tabID, liveDocument) }
        let oldRevision = owner.revision
        let old = try #require(owner.beginPreviewLoad(
            for: document, tabID: tabID,
            sourceGeneration: document.mutationGeneration, grantRevision: oldRevision,
            consumer: .markdown
        ))
        liveDocument = document.markClean()
        let current = try #require(owner.beginPreviewLoad(
            for: liveDocument, tabID: tabID,
            sourceGeneration: liveDocument.mutationGeneration, grantRevision: owner.revision,
            consumer: .markdown
        ))
        #expect(old.isRevoked)
        #expect(owner.beginPreviewLoad(
            for: document, tabID: tabID,
            sourceGeneration: document.mutationGeneration, grantRevision: oldRevision,
            consumer: .markdown
        ) == nil)
        #expect(!current.isRevoked)
        owner.retire(.markdown, matching: old)
        #expect(!current.isRevoked)
        owner.close()
    }

    @Test func cancellationAfterBackingAcquisitionCannotPublishAFolderGrant() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"))
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let owner = PreviewResourceWindowState()
        defer { owner.close() }
        let origin = try #require(owner.beginSelection(for: document))
        var reads = 0
        var request: Task<Bool, Never>?
        request = Task { @MainActor in
            do {
                try await owner.install(selection, from: origin) {
                    reads += 1
                    if reads == 2 {
                        request?.cancel()
                    }
                    return document
                }
                return true
            } catch PreviewResourceAdmissionError.revoked {
                return false
            } catch {
                Issue.record("Unexpected acquisition error: \(error)")
                return false
            }
        }
        let pending = try #require(request)
        #expect(await pending.value == false)
        #expect(reads == 2, "Cancellation must occur after the actual backing acquisition")
        #expect(!owner.hasGrant(for: document))
        let fresh = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: fresh) { document }
        #expect(owner.hasGrant(for: document), "An uncancelled current choice must still succeed")
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
