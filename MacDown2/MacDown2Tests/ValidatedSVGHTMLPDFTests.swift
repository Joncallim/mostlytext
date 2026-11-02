import ExportService
import Foundation
@testable import MacDown2
import Testing
import Themes
import WebKit

@Suite("Validated SVG HTML and PDF consumers")
struct ValidatedSVGHTMLPDFTests {
    @MainActor
    @Test func webKitLoadsCompanionImagesWithEscapedOutputNames() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("validated-webkit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ"
            + "AAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="
        let image = try #require(Data(base64Encoded: pngBase64))
        try image.write(to: folder.appendingPathComponent("pixel.png"))
        let request = try ExportRequest(
            text: "![pixel](pixel.png)\n", sourceGeneration: 1,
            theme: BundledThemes.light, documentURL: folder.appendingPathComponent("source.md"),
            resourceAccess: ExportResourceAccess(openingDirectory: folder)
        )

        for name in ["report#one?.html", "report%23one.html", "雪.html"] {
            let target = folder.appendingPathComponent(name)
            let result = try await ExportService.exportValidatedSVG(
                request, to: .html(url: target, mode: .standalone(style: .embedded)),
                lease: ExportLifetimeLease()
            )
            let companion = try #require(result.companionFiles.first { $0.pathExtension == "png" })
            #expect(try Data(contentsOf: companion) == image)

            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.loadFileURL(target, allowingReadAccessTo: folder)
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            var loaded = false
            var currentSource = ""
            while ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
                let widthValue = try? await webView.evaluateJavaScript("document.images[0]?.naturalWidth ?? 0")
                let sourceValue = try? await webView.evaluateJavaScript("document.images[0]?.currentSrc ?? ''")
                let width = widthValue as? Int ?? 0
                currentSource = sourceValue as? String ?? ""
                if width == 1 {
                    loaded = true
                    break
                }
            }
            #expect(loaded, "WebKit did not decode companion image for \(name): \(currentSource)")
            #expect(URL(string: currentSource)?.standardizedFileURL == companion.standardizedFileURL)
            webView.stopLoading()
        }
    }

    @Test func pdfAdapterInputPreservesTheAcceptedHTMLBytes() async throws {
        let source = "```diagram\nnode\n```\n"
        let diagram = #"<svg id="root"><defs><linearGradient id="paint"/></defs>"#
            + #"<rect fill="url(#paint)" width="12" height="12"/></svg>"#
        let target = URL(fileURLWithPath: "/tmp/validated-svg-pdf-\(UUID().uuidString).pdf")
        let request = ExportRequest(
            text: source, sourceGeneration: 1, theme: BundledThemes.light,
            contributions: [
                ExportDerivedContribution(sourceRange: 0 ..< source.utf16.count,
                                          placement: .block, html: diagram, sourceGeneration: 1),
            ]
        )
        let result = try await ExportService.exportValidatedSVG(
            request, to: .pdf(url: target), lease: ExportLifetimeLease()
        ) { validated, url, _ in
            let html = try await PDFExportAdapter.validatedHTMLForWebKit(validated, to: url)
            #expect(Data(html.utf8) == validated.utf8)
            #expect(html.contains("script-src 'none'"))
            #expect(!html.contains("<!--MT117-SVG-"))
            do {
                _ = try await PDFExportAdapter.validatedHTMLForWebKit(
                    validated, to: url.deletingLastPathComponent().appendingPathComponent("other.pdf")
                )
                Issue.record("A PDF receipt was accepted for another destination")
            } catch is ExportError {
                // Correct: the receipt is bound to its original destination.
            }
        }
        #expect(result.primaryFile == target)
    }
}
