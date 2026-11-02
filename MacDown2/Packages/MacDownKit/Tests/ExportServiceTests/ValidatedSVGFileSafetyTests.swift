import Darwin
@testable import ExportService
import Foundation
import MarkdownEngine
import Testing
import Themes

@Suite("Validated HTML file publication under pathname replacement")
struct ValidatedSVGFileSafetyTests {
    private struct Fixture {
        let directory: URL
        let targetURL: URL
        let validated: ValidatedExportHTML
        let resource: ExportResource

        var assets: URL {
            directory.appendingPathComponent(validated.assetsDirectoryName, isDirectory: true)
        }
    }

    private func fixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("validated-file-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let targetURL = directory.appendingPathComponent("report.html")
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: directory.appendingPathComponent("pixel.png"))
        let request = try ExportRequest(
            text: "![pixel](pixel.png)\n", sourceGeneration: 1, theme: BundledThemes.light,
            documentURL: directory.appendingPathComponent("source.md"),
            resourceAccess: ExportResourceAccess(openingDirectory: directory)
        )
        let validated = try await ExportService.prepareValidatedSVG(
            request, to: .html(url: targetURL, mode: .standalone(style: .embedded)), engine: ParseEngine()
        )
        let resource = try #require(validated.resources.first)
        try Data("old primary".utf8).write(to: targetURL)
        return Fixture(directory: directory, targetURL: targetURL, validated: validated, resource: resource)
    }

    @Test func aSubstitutedFIFOIsRejectedWithoutBlockingPublication() async throws {
        let item = try await fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        try FileManager.default.createDirectory(at: item.assets, withIntermediateDirectories: true)
        try ExportAssetOwnerMarker.bytes(
            primary: item.targetURL.lastPathComponent,
            assets: item.validated.assetsDirectoryName
        )
        .write(to: item.assets.appendingPathComponent(ExportFileWriter.markerFileName))
        let fifo = item.assets.appendingPathComponent(item.resource.identity.fileName)
        #expect(mkfifo(fifo.path, mode_t(S_IRUSR | S_IWUSR)) == 0)
        #expect(throws: ExportError.self) {
            try ExportFileWriter.writeValidatedHTML(item.validated, lease: ExportLifetimeLease())
        }
        #expect(try Data(contentsOf: item.targetURL) == Data("old primary".utf8))
    }

    @Test func replacementOfAssetsAfterStagingCannotPublishThePrimary() async throws {
        let item = try await fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let detached = item.directory.appendingPathComponent("detached-assets")
        let outside = item.directory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        var swapped = false
        #expect(throws: ExportError.self) {
            try ExportFileWriter.writeValidatedHTML(item.validated, lease: ExportLifetimeLease(), beforePromotion: {
                do {
                    try FileManager.default.moveItem(at: item.assets, to: detached)
                    try FileManager.default.createSymbolicLink(at: item.assets, withDestinationURL: outside)
                    swapped = true
                } catch {
                    Issue.record("Could not replace staged assets: \(error)")
                }
            })
        }
        #expect(swapped)
        #expect(try Data(contentsOf: item.targetURL) == Data("old primary".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func replacementDuringStagingCannotRedirectAssetWrites() async throws {
        let item = try await fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let detached = item.directory.appendingPathComponent("detached-assets")
        let outside = item.directory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        var swapped = false
        #expect(throws: ExportError.self) {
            try ExportFileWriter.writeValidatedHTML(
                item.validated, lease: ExportLifetimeLease(),
                afterCompanionDirectoryOpened: {
                    do {
                        try FileManager.default.moveItem(at: item.assets, to: detached)
                        try FileManager.default.createSymbolicLink(at: item.assets, withDestinationURL: outside)
                        swapped = true
                    } catch {
                        Issue.record("Could not replace the opened assets directory: \(error)")
                    }
                }
            )
        }
        #expect(swapped)
        #expect(try Data(contentsOf: item.targetURL) == Data("old primary".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        #expect(!FileManager.default
            .fileExists(atPath: detached.appendingPathComponent(item.resource.identity.fileName).path))
    }

    @Test func replacementOfStagedPrimaryCannotPublishDifferentBytes() async throws {
        let item = try await fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        var replaced = false
        #expect(throws: ExportError.self) {
            try ExportFileWriter.writeValidatedHTML(item.validated, lease: ExportLifetimeLease(), beforePromotion: {
                do {
                    let names = try FileManager.default.contentsOfDirectory(atPath: item.directory.path)
                    let temporary = try #require(names.first {
                        $0.hasPrefix(".mt-") && $0.hasSuffix(".html.tmp")
                    })
                    let source = item.directory.appendingPathComponent(temporary)
                    try FileManager.default.moveItem(
                        at: source, to: item.directory.appendingPathComponent("detached-primary")
                    )
                    try Data("substituted primary".utf8).write(to: source)
                    replaced = true
                } catch {
                    Issue.record("Could not replace staged primary: \(error)")
                }
            })
        }
        #expect(replaced)
        #expect(try Data(contentsOf: item.targetURL) == Data("old primary".utf8))
    }
}
