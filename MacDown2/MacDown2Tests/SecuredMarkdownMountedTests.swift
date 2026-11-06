import AppKit
import FileCore
import Foundation
import LocalResourceAccess
@testable import MacDown2
import MarkdownEngine
import Preview
import SwiftUI
import Testing
import Themes

/// The temporary fixture is selected through the test-only receipt; no native panel or persistent grant is used.
@Suite("Secured Markdown mounted attachment", .serialized)
@MainActor
struct SecuredMarkdownMountedTests {
    private let parserIdentity = UUID()

    @Test func aGrantedImageCopiesAsPNGAndLoadsAgainUnderANewDocumentGeneration() async throws {
        let (folder, imageBytes) = try makeFolderWithImage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = "![fixture](image.png)"
        let parsed = try await ParseEngine().parse(source, revision: 1)
        var document = FileDocument(fileURL: folder.appendingPathComponent("story.md"), text: source)
        let owner = PreviewResourceWindowState()
        let tabID = UUID()
        owner.setCurrentPreviewDocument { (tabID, document) }
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: origin) { document }
        let recorder = LoadIDRecorder()
        let initialInput = await PreviewResourceAdmission.shared.globalStatus().retained
        let hosting = NSHostingView(rootView: mountedView(
            document: document, parsed: parsed, tabID: tabID, owner: owner, recorder: recorder
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer {
            owner.close()
            window.orderOut(nil)
        }
        hosting.layoutSubtreeIfNeeded()
        let first = try await waitForLoad(
            after: nil,
            recorder: recorder,
            minimumRetained: initialInput + imageBytes.count
        )
        let originalPasteboard = snapshotPasteboard()
        defer { restorePasteboard(originalPasteboard) }
        try await assertGrantedImageCopies(from: hosting)

        document = document.updatingText(source).markClean()
        hosting.rootView = mountedView(
            document: document, parsed: parsed, tabID: tabID, owner: owner, recorder: recorder
        )
        hosting.layoutSubtreeIfNeeded()
        let second = try await waitForLoad(
            after: first, recorder: recorder, minimumRetained: initialInput + imageBytes.count
        )
        #expect(second != first)
        try await assertGrantedImageCopies(from: hosting)
        try await assertRevocationStopsCopy(from: hosting, owner: owner, document: document, tabID: tabID)
    }

    @Test func aNewParsedRevisionReplacesTheLoadWithoutAnotherModelEdit() async throws {
        let (folder, imageBytes) = try makeFolderWithImage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = "![fixture](image.png)"
        let engine = ParseEngine()
        let firstParse = try await engine.parse(source, revision: 1)
        let secondParse = try await engine.parse(source, revision: 2)
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"), text: source)
        let owner = PreviewResourceWindowState()
        let tabID = UUID()
        owner.setCurrentPreviewDocument { (tabID, document) }
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: origin) { document }
        let recorder = LoadIDRecorder()
        let initialInput = await PreviewResourceAdmission.shared.globalStatus().retained
        let hosting = NSHostingView(rootView: mountedView(
            document: document, parsed: firstParse, tabID: tabID, owner: owner, recorder: recorder
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer {
            owner.close()
            window.orderOut(nil)
        }
        let originalPasteboard = snapshotPasteboard()
        defer { restorePasteboard(originalPasteboard) }
        hosting.layoutSubtreeIfNeeded()
        let first = try await waitForLoad(after: nil, recorder: recorder,
                                          minimumRetained: initialInput + imageBytes.count)
        hosting.rootView = mountedView(
            document: document, parsed: secondParse, tabID: tabID, owner: owner, recorder: recorder
        )
        hosting.layoutSubtreeIfNeeded()
        let second = try await waitForLoad(after: first, recorder: recorder,
                                           minimumRetained: initialInput + imageBytes.count)
        #expect(first != second)
        try await assertGrantedImageCopies(from: hosting)
        #expect(firstParse.sourceSHA256 == secondParse.sourceSHA256)
        #expect(firstParse.revision != secondParse.revision)
    }

    @ViewBuilder
    private func mountedView(
        document: FileCore.FileDocument, parsed: MarkdownDocument, tabID: UUID,
        owner: PreviewResourceWindowState,
        recorder: LoadIDRecorder
    ) -> some View {
        if let frame = PreviewResourceParsedFrame(parserIdentity: parserIdentity, document: parsed) {
            SecuredMarkdownResourceHost(
                tabID: tabID, document: document, sourceGeneration: document.mutationGeneration,
                parsedFrame: frame
            ) { loader, loadID in
                TextualMarkdownPreview(
                    document: parsed, text: document.text,
                    theme: PreviewTheme(theme: BundledThemes.light),
                    resourceImageLoader: loader, resourceLoadID: loadID
                )
                .onChange(of: loadID, initial: true) { _, id in recorder.record(id) }
            }
            .environment(\.previewResourceWindowState, owner)
        }
    }

    private func waitForLoad(
        after prior: UUID?, recorder: LoadIDRecorder, minimumRetained: Int
    ) async throws -> UUID {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let current = recorder.lastID, current != prior,
               await PreviewResourceAdmission.shared.globalStatus().retained >= minimumRetained {
                return current
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Mounted Textual did not admit the expected document-bound image")
        throw PreviewResourceAdmissionError.limitExceeded
    }

    private func copiedHTML(from view: NSView) async throws -> String {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let interaction = findTextInteraction(in: view) {
                _ = interaction.perform(NSSelectorFromString("selectAll:"), with: nil)
                _ = interaction.perform(NSSelectorFromString("copy:"), with: nil)
                if let html = NSPasteboard.general.string(forType: .html) {
                    return html
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Mounted Textual did not produce HTML from its native copy action")
        throw PreviewResourceAdmissionError.limitExceeded
    }

    private func assertGrantedImageCopies(from view: NSView) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var lastHTML = ""
        while ContinuousClock.now < deadline {
            lastHTML = try await copiedHTML(from: view)
            if lastHTML.contains("data:image/png;base64,") {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Mounted Textual never copied its admitted image; final HTML: \(lastHTML)")
    }

    private func assertRevocationStopsCopy(
        from view: NSView, owner: PreviewResourceWindowState,
        document: FileCore.FileDocument, tabID: UUID
    ) async throws {
        owner.invalidateForIdentityChange()
        #expect(owner.beginPreviewLoad(
            for: document, tabID: tabID, sourceGeneration: document.mutationGeneration,
            grantRevision: owner.revision, consumer: .markdown
        ) == nil)
        let html = try await copiedHTML(from: view)
        #expect(!html.contains("data:image/png;base64,"))
    }

    private func findTextInteraction(in view: NSView) -> NSView? {
        if NSStringFromClass(type(of: view)).hasSuffix(".NSTextInteractionView") {
            return view
        }
        for child in view.subviews {
            if let found = findTextInteraction(in: child) {
                return found
            }
        }
        return nil
    }

    private func snapshotPasteboard() -> [NSPasteboardItem] {
        NSPasteboard.general.pasteboardItems?.map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
    }

    private func restorePasteboard(_ items: [NSPasteboardItem]) {
        NSPasteboard.general.clearContents()
        if !items.isEmpty {
            _ = NSPasteboard.general.writeObjects(items)
        }
    }

    private func smallPNG() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func makeFolderWithImage() throws -> (URL, Data) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let bytes = try smallPNG()
            try bytes.write(to: folder.appendingPathComponent("image.png"))
            return (folder, bytes)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}

@MainActor
private final class LoadIDRecorder {
    private(set) var lastID: UUID?

    func record(_ id: UUID?) {
        if let id {
            lastID = id
        }
    }
}
