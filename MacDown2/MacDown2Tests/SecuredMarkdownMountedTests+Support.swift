import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Testing

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
        windowDiagnostics.captureFailure(host: view, selected: findTextInteraction(in: view))
        let details = await diagnostic()
        Issue.record("""
        Mounted Textual never copied its admitted image; final HTML: \(lastHTML);
        \(details); \(copyDiagnostics(in: view))
        """)
    }

    func repeatedGenerationPNG(generation: Int) throws -> Data {
        let index = generation - 3
        try #require((0 ..< 10).contains(index))
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let color = NSColor(
            deviceRed: CGFloat(index % 4) / 3, green: CGFloat(index / 4) / 2,
            blue: 1, alpha: 1
        )
        for row in 0 ..< 8 {
            for column in 0 ..< 8 {
                bitmap.setColor(color, atX: column, y: row)
            }
        }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    func calibrateRepeatedImageOracle(originalImage: Data, references: [Data]) throws {
        try #require(references.count == 10, "Ten distinct repeat generations are required")
        let originalHTML = "<img src=\"data:image/png;base64,\(originalImage.base64EncodedString())\">"
        for expected in references.indices {
            for actual in references.indices {
                let html = "<img src=\"data:image/png;base64,\(references[actual].base64EncodedString())\">"
                try #require(copiedImageMatchesPixels(html, reference: references[expected]) == (actual == expected))
            }
            try #require(!copiedImageMatchesPixels(originalHTML, reference: references[expected]))
        }
        print("MOUNTED_IMAGE_ORACLE positives=10 negatives=100")
    }

    func assertGenerationImageCopies(
        from view: NSView, reference: Data, generation: Int,
        before deadline: ContinuousClock.Instant, diagnostic: @MainActor () async -> String
    ) async throws {
        var lastHTML: String?
        while ContinuousClock.now < deadline {
            if let interaction = findTextInteraction(in: view),
               let html = freshNativeCopiedHTML(from: interaction) {
                lastHTML = html
                if copiedImageMatchesPixels(html, reference: reference) {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        windowDiagnostics.captureFailure(host: view, selected: findTextInteraction(in: view))
        let details = await diagnostic()
        Issue.record("""
        Mounted Textual copied the wrong image for generation \(generation); \
        expectedPixels=\(String(describing: imagePixelComponents(reference))) \
        actualPixels=\(String(describing: lastHTML.flatMap(copiedImagePixelComponents))) \
        finalHTML=\(lastHTML ?? "<no fresh HTML>"); \(details); \(copyDiagnostics(in: view))
        """)
    }

    private func copiedImageMatchesPixels(_ html: String, reference: Data) -> Bool {
        guard let actual = copiedImagePixelComponents(html),
              let expected = imagePixelComponents(reference)
        else { return false }
        return zip(actual, expected).allSatisfy { abs($0 - $1) < 0.1 }
    }

    private func copiedImagePixelComponents(_ html: String) -> [CGFloat]? {
        guard let start = html.range(of: "data:image/png;base64,")?.upperBound else { return nil }
        let encoded = html[start...].prefix { $0.isLetter || $0.isNumber || "+/=".contains($0) }
        guard let bytes = Data(base64Encoded: String(encoded)) else { return nil }
        return imagePixelComponents(bytes)
    }

    private func imagePixelComponents(_ bytes: Data) -> [CGFloat]? {
        guard bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let image = NSBitmapImageRep(data: bytes), image.pixelsWide == 8, image.pixelsHigh == 8,
              let topLeft = image.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB),
              let bottomRight = image.colorAt(x: 7, y: 7)?.usingColorSpace(.sRGB)
        else { return nil }
        return [topLeft, bottomRight].flatMap {
            [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent]
        }
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
            let modelID = (interaction as? Textual.NSTextInteractionView).map { ObjectIdentifier($0.model) }
            return "view=\(ObjectIdentifier(interaction)) hidden=\(interaction.isHiddenOrHasHiddenAncestor) "
                + "modelID=\(String(describing: modelID)) frame=\(interaction.frame) "
                + "firstResponder=\(interaction.window?.firstResponder === interaction) "
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
