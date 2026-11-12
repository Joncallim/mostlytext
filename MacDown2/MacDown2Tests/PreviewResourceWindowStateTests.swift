import FileCore
import Foundation
@testable import MacDown2
import Testing

@Suite("Preview window resource ownership")
@MainActor
struct PreviewResourceWindowStateTests {
    @Test func scopeStartStopBalancesAcrossLoadSupersedeAndWindowClose() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = FileDocument(fileURL: folder.appendingPathComponent("first.md"))
        let second = FileDocument(fileURL: folder.appendingPathComponent("second.md"))
        let owner = PreviewResourceWindowState()
        let counter = PreviewScopeCounter()

        let firstURL = try #require(first.fileURL)
        let firstSelection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: firstURL, folderURL: folder
        ))
        let firstOrigin = try #require(owner.beginSelection(for: first))
        try await owner.install(firstSelection, from: firstOrigin, scopeAccess: counter.access) { first }
        let load = try #require(owner.beginLoad(for: first, consumer: .html))
        var use = load.acquireUse()
        #expect(use != nil)
        #expect(counter.started == [folder])
        #expect(counter.stopped.isEmpty)

        owner.invalidateForIdentityChange()
        #expect(load.isRevoked)
        #expect(counter.stopped.isEmpty, "An admitted read retains its real scope after supersede")
        use = nil
        try await counter.waitForStops(1)
        #expect(counter.stopped == [folder])

        let secondURL = try #require(second.fileURL)
        let secondSelection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: secondURL, folderURL: folder
        ))
        let secondOrigin = try #require(owner.beginSelection(for: second))
        try await owner.install(secondSelection, from: secondOrigin, scopeAccess: counter.access) { second }
        #expect(counter.started == [folder, folder])
        #expect(counter.stopped == [folder])
        owner.close()
        try await counter.waitForStops(2)
        #expect(counter.stopped == [folder, folder])
        owner.close()
        #expect(counter.stopped.count == 2)
    }

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
        let counter = PreviewScopeCounter()
        var reads = 0
        await #expect(throws: PreviewResourceAdmissionError.revoked) {
            try await owner.install(selection, from: origin, scopeAccess: counter.access) {
                reads += 1
                return reads == 1 ? document : other
            }
        }
        #expect(counter.started == [folder])
        try await counter.waitForStops(1)
        #expect(counter.stopped == [folder])
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
