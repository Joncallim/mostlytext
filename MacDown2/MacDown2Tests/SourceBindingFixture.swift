import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Testing

/// A single real mounted resource consumer, without a competing document controller.
@MainActor
final class SourceBindingFixture {
    let folder: URL
    let document: FileCore.FileDocument
    let tabID = UUID()
    let owner = PreviewResourceWindowState()
    let copyHarness = SecuredMarkdownMountedTests()

    init(source: String) async throws {
        let (folder, _) = try copyHarness.makeFolderWithImage()
        self.folder = folder
        let document = FileCore.FileDocument(fileURL: folder.appendingPathComponent("story.md"), text: source)
        self.document = document
        let tabID = tabID
        owner.setCurrentPreviewDocument { (tabID, document) }
        do {
            let url = try #require(document.fileURL)
            let receipt = try #require(PreviewResourceFolderSelection.fixture(documentURL: url, folderURL: folder))
            let origin = try #require(owner.beginSelection(for: document))
            try await owner.install(receipt, from: origin) { document }
            try #require(owner.hasGrant(for: document))
        } catch {
            dispose()
            throw error
        }
    }

    func dispose() {
        owner.close()
        owner.setCurrentPreviewDocument(nil)
        try? FileManager.default.removeItem(at: folder)
    }

    func wait(_ message: String, until ready: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if ready() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("\(message)")
        throw PreviewResourceAdmissionError.limitExceeded
    }
}
