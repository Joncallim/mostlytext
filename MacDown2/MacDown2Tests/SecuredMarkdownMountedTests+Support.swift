import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Testing

extension SecuredMarkdownMountedTests {
    func copiedHTML(from view: NSView) async throws -> String {
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

    func assertGrantedImageCopies(from view: NSView) async throws {
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

    func assertRevocationStopsCopy(
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

    func findTextInteraction(in view: NSView) -> NSView? {
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

    func snapshotPasteboard() -> [NSPasteboardItem] {
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

    func restorePasteboard(_ items: [NSPasteboardItem]) {
        NSPasteboard.general.clearContents()
        if !items.isEmpty {
            _ = NSPasteboard.general.writeObjects(items)
        }
    }

    func smallPNG() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    func makeFolderWithImage() throws -> (URL, Data) {
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
