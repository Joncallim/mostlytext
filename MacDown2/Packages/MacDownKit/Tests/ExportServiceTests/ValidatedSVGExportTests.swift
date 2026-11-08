@testable import ExportService
import Foundation
import MarkdownEngine
import Testing
import Themes

@Suite("Validated SVG export publication")
struct ValidatedSVGExportTests {
    private let source = "```diagram\nnode\n```\n"
    private let artwork = #"<svg id="root" width="12" height="12"><defs>"#
        + #"<linearGradient id="paint"/></defs><rect width="12" height="12" fill="url(#paint)"/></svg>"#

    @Test func completeHTMLWritesTheExactAcceptedUTF8Bytes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = ExportTarget.html(url: directory.appendingPathComponent("unicode.html"), mode: .selfContained)
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: directory.appendingPathComponent("pixel.png"))
        let request = makeRequest(text: source + "\n雪と𝛼\n\n![pixel](pixel.png)\n",
                                  documentURL: directory.appendingPathComponent("source.md"))
        let validated = try await ExportService.prepareValidatedSVG(request, to: target, engine: ParseEngine())
        #expect(validated.matches(target: target, sourceText: request.text, generation: 1))
        #expect(!validated.matches(target: target, sourceText: request.text + " ", generation: 1))
        #expect(!validated.matches(target: target, sourceText: request.text, generation: 2))
        let result = try ExportFileWriter.writeValidatedHTML(validated, lease: ExportLifetimeLease())
        #expect(try Data(contentsOf: result.primaryFile) == validated.utf8)
        let html = try #require(String(data: validated.utf8, encoding: .utf8))
        #expect(html.contains("雪と𝛼"))
        #expect(html.contains("data:image/png;base64,"))
        #expect(html.contains("script-src 'none'"))
        #expect(html.contains("mt117-svg-0-0-paint"))
        #expect(!html.contains("<!--MT117-SVG-"))
    }

    @Test func unresolvedGeneratedPaintFallsBackToTheAuthoredFence() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = ExportTarget.html(url: directory.appendingPathComponent("fallback.html"), mode: .selfContained)
        let request = makeRequest(html: #"<svg><rect fill="url(#missing)"/></svg>"#)
        let validated = try await ExportService.prepareValidatedSVG(request, to: target, engine: ParseEngine())
        let html = try #require(String(data: validated.utf8, encoding: .utf8))
        #expect(html.contains("<pre><code"))
        #expect(html.contains("node"))
        #expect(!html.contains("<svg"))
        #expect(validated.diagnostics.contains { $0.message.contains("source preserved") })
    }

    @Test func aBrowserReparentedDiagramGetsOneFreshSourceFallback() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = ExportTarget.html(url: directory.appendingPathComponent("fallback.html"), mode: .selfContained)
        let request = makeRequest(html: "<table>\(artwork)</table>")
        let validated = try await ExportService.prepareValidatedSVG(request, to: target, engine: ParseEngine())
        let html = try #require(String(data: validated.utf8, encoding: .utf8))
        #expect(html.contains("<pre><code"))
        #expect(!html.contains("<svg"))
        #expect(validated.diagnostics.contains {
            $0.message == "generated diagram could not be safely isolated; authored source preserved"
        })
    }

    @Test func aConflictingAssetNeverReplacesTheOldPrimary() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appendingPathComponent("report.html")
        let target = ExportTarget.html(url: targetURL, mode: .standalone(style: .embedded))
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: directory.appendingPathComponent("pixel.png"))
        let request = makeRequest(text: source + "\n![pixel](pixel.png)\n",
                                  documentURL: directory.appendingPathComponent("source.md"))
        let validated = try await ExportService.prepareValidatedSVG(request, to: target, engine: ParseEngine())
        let resource = try #require(validated.resources.first)
        let assets = directory.appendingPathComponent(validated.assetsDirectoryName)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try ExportAssetOwnerMarker.bytes(primary: targetURL.lastPathComponent, assets: validated.assetsDirectoryName)
            .write(to: assets.appendingPathComponent(ExportFileWriter.markerFileName))
        let path = assets.appendingPathComponent(resource.identity.fileName)
        try Data("old asset".utf8).write(to: path)
        try Data("old primary".utf8).write(to: targetURL)
        #expect(throws: ExportError.self) {
            try ExportFileWriter.writeValidatedHTML(validated, lease: ExportLifetimeLease())
        }
        #expect(try Data(contentsOf: targetURL) == Data("old primary".utf8))
        #expect(try Data(contentsOf: path) == Data("old asset".utf8))
    }

    @Test func revocationAfterCompanionStagingLeavesThePrimaryUntouched() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appendingPathComponent("report.html")
        let target = ExportTarget.html(url: targetURL, mode: .standalone(style: .embedded))
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: directory.appendingPathComponent("pixel.png"))
        let request = makeRequest(text: source + "\n![pixel](pixel.png)\n",
                                  documentURL: directory.appendingPathComponent("source.md"))
        let validated = try await ExportService.prepareValidatedSVG(request, to: target, engine: ParseEngine())
        let resource = try #require(validated.resources.first)
        try Data("old primary".utf8).write(to: targetURL)
        let lease = ExportLifetimeLease()
        var staged = false
        #expect(throws: CancellationError.self) {
            try ExportFileWriter.writeValidatedHTML(validated, lease: lease, beforePromotion: {
                staged = FileManager.default.fileExists(atPath: directory
                    .appendingPathComponent(validated.assetsDirectoryName)
                    .appendingPathComponent(resource.identity.fileName).path)
                lease.revoke()
            })
        }
        #expect(staged)
        #expect(try Data(contentsOf: targetURL) == Data("old primary".utf8))
    }

    @Test func aSymlinkedAssetDirectoryCannotRedirectStaging() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appendingPathComponent("report.html")
        let target = ExportTarget.html(url: targetURL, mode: .standalone(style: .embedded))
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: directory.appendingPathComponent("pixel.png"))
        let request = makeRequest(text: source + "\n![pixel](pixel.png)\n",
                                  documentURL: directory.appendingPathComponent("source.md"))
        let validated = try await ExportService.prepareValidatedSVG(request, to: target, engine: ParseEngine())
        let outside = directory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent(validated.assetsDirectoryName), withDestinationURL: outside
        )
        try Data("old primary".utf8).write(to: targetURL)
        #expect(throws: ExportError.self) {
            try ExportFileWriter.writeValidatedHTML(validated, lease: ExportLifetimeLease())
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        #expect(try Data(contentsOf: targetURL) == Data("old primary".utf8))
    }

    @Test func aSymlinkedExistingAssetCannotBeAcceptedEvenWhenItsBytesMatch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appendingPathComponent("report.html")
        let target = ExportTarget.html(url: targetURL, mode: .standalone(style: .embedded))
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: directory.appendingPathComponent("pixel.png"))
        let request = makeRequest(text: source + "\n![pixel](pixel.png)\n",
                                  documentURL: directory.appendingPathComponent("source.md"))
        let validated = try await ExportService.prepareValidatedSVG(request, to: target, engine: ParseEngine())
        let resource = try #require(validated.resources.first)
        let assets = directory.appendingPathComponent(validated.assetsDirectoryName)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try ExportAssetOwnerMarker.bytes(primary: targetURL.lastPathComponent, assets: validated.assetsDirectoryName)
            .write(to: assets.appendingPathComponent(ExportFileWriter.markerFileName))
        let outside = directory.appendingPathComponent("outside.png")
        try resource.bytes.write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: assets.appendingPathComponent(resource.identity.fileName), withDestinationURL: outside
        )
        try Data("old primary".utf8).write(to: targetURL)
        #expect(throws: ExportError.self) {
            try ExportFileWriter.writeValidatedHTML(validated, lease: ExportLifetimeLease())
        }
        #expect(try Data(contentsOf: outside) == resource.bytes)
        #expect(try Data(contentsOf: targetURL) == Data("old primary".utf8))
    }

    private func makeRequest(html: String? = nil, text: String? = nil,
                             documentURL: URL? = nil) -> ExportRequest {
        let text = text ?? source
        return ExportRequest(
            text: text, sourceGeneration: 1, theme: BundledThemes.light,
            documentURL: documentURL,
            resourceAccess: documentURL
                .flatMap { try? ExportResourceAccess(openingDirectory: $0.deletingLastPathComponent()) },
            contributions: [
                ExportDerivedContribution(
                    sourceRange: 0 ..< source.utf16.count, placement: .block,
                    html: html ?? artwork, sourceGeneration: 1
                ),
            ]
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("validated-svg-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

extension ValidatedSVGExportTests {
    @Test func pdfCanvasPolicyIsCoveredBySVGValidationAndLeavesHTMLScrollbarsAlone() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = makeRequest()
        let htmlTarget = ExportTarget.html(url: directory.appendingPathComponent("report.html"), mode: .selfContained)
        let pdfTarget = ExportTarget.pdf(url: directory.appendingPathComponent("report.pdf"))
        let html = try await ExportService.prepareValidatedSVG(request, to: htmlTarget, engine: ParseEngine())
        let pdf = try await ExportService.prepareValidatedSVG(request, to: pdfTarget, engine: ParseEngine())
        let htmlText = try #require(String(data: html.utf8, encoding: .utf8))
        let pdfText = try #require(String(data: pdf.utf8, encoding: .utf8))
        #expect(htmlText.contains("<svg") && pdfText.contains("<svg"), "The audited diagram must not fall back")
        #expect(!htmlText.contains("scrollbar-width:"))
        #expect(pdfText.contains("html { scrollbar-width: none !important; }"))
        #expect(pdf.matches(target: pdfTarget, sourceText: request.text, generation: 1))
        #expect(!html.isForPDF(at: directory.appendingPathComponent("report.pdf")))
    }
}
