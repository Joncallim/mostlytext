import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Testing
import Textual

extension SecuredMarkdownMountedTests {
    func copiedHTML(from view: NSView) async throws -> String {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let interaction = findTextInteraction(in: view),
               let html = freshNativeCopiedHTML(from: interaction) {
                return html
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        windowDiagnostics.captureFailure(host: view, selected: findTextInteraction(in: view))
        Issue.record("Mounted Textual did not produce HTML from its native copy action")
        throw PreviewResourceAdmissionError.limitExceeded
    }

    /// A no-write native action must not reuse HTML from any earlier copy.
    func freshNativeCopiedHTML(from interaction: NSView) -> String? {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let clearedGeneration = pasteboard.changeCount
        _ = interaction.perform(NSSelectorFromString("selectAll:"), with: nil)
        _ = interaction.perform(NSSelectorFromString("copy:"), with: nil)
        guard pasteboard.changeCount > clearedGeneration else { return nil }
        return pasteboard.string(forType: .html)
    }

    func assertGrantedImageCopies(
        from view: NSView, diagnostic: @MainActor () async -> String
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var lastHTML = ""
        while ContinuousClock.now < deadline {
            do {
                lastHTML = try await copiedHTML(from: view)
            } catch {
                MostlyTextPublicationTrace.markCopyFailure("mounted-copy-command-refused")
                windowDiagnostics.captureFailure(host: view, selected: findTextInteraction(in: view))
                let details = await diagnostic()
                print("MOUNTED_COPY_DIAGNOSTIC \(details) \(copyDiagnostics(in: view))")
                throw error
            }
            if lastHTML.contains("data:image/png;base64,") {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        MostlyTextPublicationTrace.markCopyFailure("mounted-image-copy-deadline")
        windowDiagnostics.captureFailure(host: view, selected: findTextInteraction(in: view))
        let details = await diagnostic()
        Issue.record("""
        Mounted Textual never copied its admitted image; final HTML: \(lastHTML);
        \(details); \(copyDiagnostics(in: view))
        """)
    }

    func makeMountedWindow(hosting: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = hosting
        windowDiagnostics.observe(window, host: hosting)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    func copyDiagnostics(in view: NSView) -> String {
        let original = snapshotPasteboard()
        defer { restorePasteboard(original) }
        return textInteractions(in: view).map { interaction in
            guard interaction.responds(to: NSSelectorFromString("selectAll:")),
                  interaction.responds(to: NSSelectorFromString("copy:"))
            else { return "view=\(ObjectIdentifier(interaction)) lacks native copy selectors" }
            _ = interaction.perform(NSSelectorFromString("selectAll:"), with: nil)
            _ = interaction.perform(NSSelectorFromString("copy:"), with: nil)
            let html = NSPasteboard.general.string(forType: .html) ?? "<no HTML>"
            return "view=\(ObjectIdentifier(interaction)) hidden=\(interaction.isHiddenOrHasHiddenAncestor) "
                + "frame=\(interaction.frame) firstResponder=\(interaction.window?.firstResponder === interaction) "
                + "html=\(html) \(attachmentLayoutDiagnostics(in: interaction))"
        }.joined(separator: " | ")
    }

    private func textInteractions(in view: NSView) -> [NSView] {
        let current = NSStringFromClass(type(of: view)).hasSuffix(".NSTextInteractionView") ? [view] : []
        return current + view.subviews.flatMap { textInteractions(in: $0) }
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
