import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Preview
import Testing
import Textual
import WebKit

@MainActor
@Suite("Production Preview resource routing", .serialized)
struct ProductionPreviewResourceRoutingTests {
    @Test func theRealMarkdownWindowCopiesGrantedImagesAndRevokesThemOnSaveAs() async throws {
        let source = "![fixture](image.png)\n"
        let fixture = try PreviewProductionFixture(source: source, previewLayout: .split(fraction: 0.5))
        defer { fixture.dispose() }
        let pasteboard = fixture.copyHarness.snapshotPasteboard()
        defer { fixture.copyHarness.restorePasteboard(pasteboard) }
        let receipt = try fixture.selection()
        let request = try #require(fixture.coordinator
            .beginPreviewResourceSelection(from: fixture.first) { window, url in
                #expect(window === fixture.first.window)
                #expect(url == receipt.requestedDocumentURL)
                return receipt
            })
        #expect(await request.value)
        let root = try fixture.root()
        try await fixture.copyHarness.assertGrantedImageCopies(from: root) {
            "actual WindowController / WorkspaceShell / DocumentEditorSplitView Preview"
        }
        try await assertNewDocumentGenerationCopiesItsCurrentImage(fixture, root: root)
        let before = try #require(fixture.first.model.activeDocument)
        let destination = fixture.folder.appendingPathComponent("same-text-save-as.md")
        await fixture.first.model.saveAs(to: destination, expecting: before)
        let current = try #require(fixture.first.model.activeDocument)
        #expect(current.fileURL == destination)
        #expect(current.text.utf8.elementsEqual(before.text.utf8))
        #expect(!fixture.first.previewResourceState.hasGrant(for: current))
        let html = try await fixture.copyHarness.copiedHTML(from: root)
        #expect(!html.contains("data:image/png;base64,"), "The production Save As path must revoke copied resources")
    }

    @Test func theRealHTMLPaneUsesImmutableHandlersAndPreservesSourceRenderedSwitching() async throws {
        let firstSource = "<html><head><title>Production A</title></head><body>A</body></html>"
        let secondSource = "<html><head><title>Production B</title></head><body>B</body></html>"
        let fixture = try PreviewProductionFixture(source: firstSource, name: "source.html")
        defer { fixture.dispose() }
        let root = try fixture.root()
        let first = try await page("Production A", in: root, fixture: fixture)
        let firstHandler = try #require(first.configuration.urlSchemeHandler(
            forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme
        ) as? BoundedHTMLPreviewHandler)
        #expect(first.url == firstHandler.load.mainURL)
        #expect(String(data: firstHandler.load.mainData, encoding: .utf8)?.contains("Production A") == true)

        let receipt = try fixture.selection()
        let request = try #require(fixture.coordinator.beginPreviewResourceSelection(from: fixture.first) { _, _ in
            receipt
        })
        #expect(await request.value)
        let granted = try await page("Production A", in: root, fixture: fixture, excluding: first)
        #expect(granted !== first)
        fixture.first.model.tabStore.updateActiveDocument { $0.updatingText(secondSource).markClean() }
        let second = try await page("Production B", in: root, fixture: fixture)
        let secondHandler = try #require(second.configuration.urlSchemeHandler(
            forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme
        ) as? BoundedHTMLPreviewHandler)
        #expect(second !== granted)
        #expect(secondHandler.load.authority != firstHandler.load.authority)
        #expect(String(data: firstHandler.load.mainData, encoding: .utf8)?.contains("Production A") == true)
        #expect(String(data: secondHandler.load.mainData, encoding: .utf8)?.contains("Production B") == true)

        let tab = try #require(fixture.first.model.tabStore.activeTabID)
        fixture.first.model.tabStore.setPreviewMode(.source, for: tab)
        try await fixture.wait("The real HTML Source picker did not expose the current source") {
            let views = PreviewProductionFixture.descendants(root)
            return !views.contains { $0 is WKWebView }
                && views.compactMap { $0 as? NSTextView }.contains { $0.string.utf8.elementsEqual(secondSource.utf8) }
        }
        fixture.first.model.tabStore.setPreviewMode(.rendered, for: tab)
        let restored = try await page("Production B", in: root, fixture: fixture)
        #expect(restored !== second)
        #expect(restored.configuration.urlSchemeHandler(
            forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme
        ) is BoundedHTMLPreviewHandler)
    }

    private func page(
        _ title: String, in root: NSView, fixture: PreviewProductionFixture, excluding previous: WKWebView? = nil
    ) async throws -> WKWebView {
        var matched: WKWebView?
        try await fixture.wait("Production HTML did not finish its immutable page: \(title)") {
            matched = PreviewProductionFixture.descendants(root).compactMap { $0 as? WKWebView }.first {
                $0 !== previous && $0.title == title
            }
            return matched != nil
        }
        return try #require(matched)
    }

    private func assertNewDocumentGenerationCopiesItsCurrentImage(
        _ fixture: PreviewProductionFixture, root: NSView
    ) async throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        for column in 0 ..< 2 {
            for row in 0 ..< 2 {
                bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: column, y: row)
            }
        }
        let bytes = try #require(bitmap.representation(using: .png, properties: [:]))
        let encoded = try #require(NSBitmapImageRep(data: bytes))
        let fixtureColor = try #require(encoded.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        try #require(encoded.pixelsWide == 2 && encoded.pixelsHigh == 2)
        try #require(fixtureColor.blueComponent > 0.9 && fixtureColor.redComponent < 0.1)
        try bytes.write(to: fixture.folder.appendingPathComponent("second.png"))
        let tabID = try #require(fixture.first.model.tabStore.activeTabID)
        let system = try #require(fixture.first.editorStore.existingSystem(for: tabID.uuidString))
        try #require(system.textView.window === fixture.first.window)
        try #require(system.textView.delegate != nil)
        let priorGeneration = try #require(fixture.first.model.activeDocument).mutationGeneration
        let replacement = "![second](second.png)\n"
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        system.textView.insertText(replacement, replacementRange: NSRange(location: 0, length: system.text.utf16.count))
        let edited = try #require(fixture.first.model.activeDocument)
        try #require(edited.text.utf8.elementsEqual(replacement.utf8))
        try #require(system.textView.string.utf8.elementsEqual(replacement.utf8))
        try #require(edited.mutationGeneration > priorGeneration)
        var lastHTML = ""
        var lastRaster = "no copied raster"
        while ContinuousClock.now < deadline {
            let html = try await fixture.copyHarness.copiedHTML(from: root)
            lastHTML = html
            if let start = html.range(of: "data:image/png;base64,")?.upperBound {
                let encoded = html[start...].prefix { $0.isLetter || $0.isNumber || "+/=".contains($0) }
                if let data = Data(base64Encoded: String(encoded)), let image = NSBitmapImageRep(data: data) {
                    let color = image.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
                    lastRaster = "copied=\(image.pixelsWide)x\(image.pixelsHigh) color=\(String(describing: color))"
                    if image.pixelsWide == 2, image.pixelsHigh == 2,
                       let color, color.blueComponent > 0.9, color.redComponent < 0.1 {
                        return
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        MostlyTextPublicationTrace.markCopyFailure("production-generation-copy-deadline")
        Issue.record("""
        The actual production Preview did not copy the current generation's distinct image pixels;
        \(lastRaster); html=\(lastHTML); \(fixture.copyHarness.copyDiagnostics(in: root))
        """)
    }
}
