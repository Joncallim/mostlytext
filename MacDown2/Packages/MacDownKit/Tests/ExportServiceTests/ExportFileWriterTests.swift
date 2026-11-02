@testable import ExportService
import Foundation
import Testing
import Themes

/// Slice 2: companion-directory ownership and primary-last durability.
struct ExportFileWriterTests {
    private func makePrepared(bodyHTML: String, resources: [ExportResource] = []) throws -> PreparedExportDocument {
        try ExportSlotTestSupport.registeringGeneratedImages(PreparedExportDocument(
            title: "Title",
            bodyHTML: bodyHTML,
            stylesheet: "body { color: var(--md-foreground); }",
            manifest: ExportManifest(resources: resources, referenceMap: [:]),
            diagnostics: [],
            sourceGeneration: 1,
            preservesRawHTML: true
        ))
    }

    private func pngResource() -> ExportResource {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        return ExportResource(identity: ExportResourceIdentity(bytes: bytes, mimeType: "image/png"), bytes: bytes)
    }

    @Test func selfContainedWritesASingleFile() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resource = pngResource()
        let assetsDir = ExportHTMLWriter.defaultAssetsDirectoryName
        let prepared = try makePrepared(
            bodyHTML: "<p><img src=\"\(assetsDir)/\(resource.identity.fileName)\"></p>",
            resources: [resource]
        )
        let target = ExportTarget.html(
            url: directory.appendingPathComponent("report.html"),
            mode: .selfContained
        )

        let result = try ExportFileWriter.writeHTML(prepared, to: target)

        #expect(result.companionFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: result.primaryFile.path))
        let html = try String(contentsOf: result.primaryFile, encoding: .utf8)
        #expect(html.contains("data:image/png;base64,"))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(assetsDir).path))
    }

    @Test func standaloneWritesAssetsWithMarker() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resource = pngResource()
        let assetsDir = ExportHTMLWriter.defaultAssetsDirectoryName
        let prepared = try makePrepared(
            bodyHTML: "<p><img src=\"\(assetsDir)/\(resource.identity.fileName)\"></p>",
            resources: [resource]
        )
        let target = ExportTarget.html(
            url: directory.appendingPathComponent("report.html"),
            mode: .standalone(style: .embedded)
        )

        let result = try ExportFileWriter.writeHTML(prepared, to: target)

        #expect(FileManager.default.fileExists(atPath: result.primaryFile.path))
        let assetsURL = directory.appendingPathComponent(assetsDir)
        #expect(FileManager.default.fileExists(atPath: assetsURL.path))
        #expect(FileManager.default
            .fileExists(atPath: assetsURL.appendingPathComponent(resource.identity.fileName).path))

        let marker = assetsURL.appendingPathComponent(ExportFileWriter.markerFileName)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(try Data(contentsOf: marker) == ExportAssetOwnerMarker.bytes(primary: "report.html", assets: assetsDir))
    }

    @Test func linkedStandaloneWritesStylesheetIntoTheAssetsDirectory() throws {
        // The linked stylesheet is a managed, content-addressed resource now —
        // not a bare `report.css` beside the primary file — so it shares the
        // same ownership and dedup guarantees as every image resource.
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = try makePrepared(bodyHTML: "<p>hi</p>")
        let target = ExportTarget.html(
            url: directory.appendingPathComponent("report.html"),
            mode: .standalone(style: .linked)
        )

        let result = try ExportFileWriter.writeHTML(prepared, to: target)

        let stylesheetResource = ExportHTMLWriter.linkedStylesheetResource(for: prepared.stylesheet)
        let assetsDir = directory.appendingPathComponent(ExportHTMLWriter.defaultAssetsDirectoryName)
        let cssURL = assetsDir.appendingPathComponent(stylesheetResource.identity.fileName)
        #expect(FileManager.default.fileExists(atPath: cssURL.path))
        #expect(result.companionFiles.contains(cssURL))
        #expect(try Data(contentsOf: cssURL) == stylesheetResource.bytes)

        let marker = assetsDir.appendingPathComponent(ExportFileWriter.markerFileName)
        #expect(FileManager.default.fileExists(atPath: marker.path))

        let html = try String(contentsOf: result.primaryFile, encoding: .utf8)
        let expectedHref = "\(ExportHTMLWriter.defaultAssetsDirectoryName)/\(stylesheetResource.identity.fileName)"
        #expect(html.contains("<link rel=\"stylesheet\" href=\"\(expectedHref)\">"))
    }

    @Test func linkedStandaloneWithNoImagesStillGetsAnAssetsDirectory() throws {
        // Zero images must not skip creating the assets directory when linked
        // CSS still needs somewhere to live.
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = try makePrepared(bodyHTML: "<p>no images</p>")
        let target = ExportTarget.html(
            url: directory.appendingPathComponent("report.html"),
            mode: .standalone(style: .linked)
        )

        let result = try ExportFileWriter.writeHTML(prepared, to: target)

        #expect(result.companionFiles.count == 2) // marker + stylesheet
        let assetsDir = directory.appendingPathComponent(ExportHTMLWriter.defaultAssetsDirectoryName)
        #expect(FileManager.default.fileExists(atPath: assetsDir.path))
    }

    @Test func neverDeletesNonReservedUserFiles() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assetsDir = directory.appendingPathComponent(ExportHTMLWriter.defaultAssetsDirectoryName)
        let userFile = assetsDir.appendingPathComponent("user-notes.txt")

        let resource = pngResource()
        let assetsDirName = ExportHTMLWriter.defaultAssetsDirectoryName
        let prepared = try makePrepared(
            bodyHTML: "<p><img src=\"\(assetsDirName)/\(resource.identity.fileName)\"></p>",
            resources: [resource]
        )
        let target = ExportTarget.html(
            url: directory.appendingPathComponent("report.html"),
            mode: .standalone(style: .embedded)
        )

        _ = try ExportFileWriter.writeHTML(prepared, to: target)
        try Data("keep me".utf8).write(to: userFile)
        _ = try ExportFileWriter.writeHTML(prepared, to: target)

        #expect(FileManager.default.fileExists(atPath: userFile.path))
        #expect(try String(contentsOf: userFile, encoding: .utf8) == "keep me")
    }

    @Test func writeHTMLRejectsPDFTarget() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = try makePrepared(bodyHTML: "<p>hi</p>")

        #expect(throws: ExportError.self) {
            try ExportFileWriter.writeHTML(prepared, to: .pdf(url: directory.appendingPathComponent("out.pdf")))
        }
    }

    @Test func everyResourceIsEmbeddedInOnePass() throws {
        // One scan must place every data URI: an image-heavy document is where a
        // per-resource rescan would quietly turn into quadratic work.
        let resources = (0 ..< 5).map { index -> ExportResource in
            let bytes = Data([0x89, 0x50, UInt8(index)])
            return ExportResource(
                identity: ExportResourceIdentity(bytes: bytes, mimeType: "image/png"),
                bytes: bytes
            )
        }
        let assetsDir = ExportHTMLWriter.defaultAssetsDirectoryName
        let body = resources
            .map { "<img src=\"\(assetsDir)/\($0.identity.fileName)\" alt=\"x\">" }
            .joined(separator: "\n")
        let prepared = try makePrepared(bodyHTML: body, resources: resources)

        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)

        #expect(!html.contains("\(assetsDir)/"))
        for resource in resources {
            let uri = "data:image/png;base64,\(resource.bytes.base64EncodedString())"
            #expect(html.contains(uri), "missing data URI for \(resource.identity.fileName)")
        }
        // Surrounding markup is preserved exactly.
        #expect(html.contains("alt=\"x\""))
    }

    @Test func unknownCompanionReferencesAreLeftAlone() throws {
        let resource = pngResource()
        let assetsDir = ExportHTMLWriter.defaultAssetsDirectoryName
        let body = "<img src=\"\(assetsDir)/not-a-resource.png\">"
        let prepared = try makePrepared(bodyHTML: body, resources: [resource])

        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)

        #expect(html.contains("\(assetsDir)/not-a-resource.png"))
    }

    @Test func aDocumentWithoutResourcesWritesNoCompanionDirectory() throws {
        // An empty assets folder beside every export is litter.
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = try makePrepared(bodyHTML: "<p>no images here</p>")
        let target = ExportTarget.html(
            url: directory.appendingPathComponent("report.html"),
            mode: .standalone(style: .embedded)
        )

        let result = try ExportFileWriter.writeHTML(prepared, to: target)

        #expect(result.companionFiles.isEmpty)
        let assetsDir = directory.appendingPathComponent(ExportHTMLWriter.defaultAssetsDirectoryName)
        #expect(!FileManager.default.fileExists(atPath: assetsDir.path))
    }

    // MARK: - Companion isolation across documents

    @Test func twoDocumentsInOneFolderGetDistinctAssetsDirectories() async throws {
        // The reviewer's exact failure mode: exporting `Beta.html` after
        // `Alpha.html` into the same folder must not touch Alpha's companions
        // — a shared `report.assets`/`report.css` would let the second export
        // silently rewrite the first document's linked stylesheet and images.
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "alpha.png", in: directory, bytes: Data([0x01, 0x02]))
        try ExportTestSupport.writeFixture(named: "beta.png", in: directory, bytes: Data([0x03, 0x04, 0x05]))

        let alphaURL = directory.appendingPathComponent("Alpha.html")
        let betaURL = directory.appendingPathComponent("Beta.html")
        let alphaAssetsDirName = ExportHTMLWriter.assetsDirectoryName(for: alphaURL)
        let betaAssetsDirName = ExportHTMLWriter.assetsDirectoryName(for: betaURL)
        #expect(alphaAssetsDirName != betaAssetsDirName)

        let alphaResult = try await ExportService.exportHTML(
            ExportRequest(
                text: "# Alpha\n\n![a](alpha.png)\n",
                sourceGeneration: 1,
                theme: ExportTestSupport.lightTheme(),
                documentURL: directory.appendingPathComponent("Alpha.md"),
                resourceAccess: ExportResourceAccess(openingDirectory: directory)
            ),
            to: .html(url: alphaURL, mode: .standalone(style: .linked))
        )
        let alphaHTMLBefore = try String(contentsOf: alphaURL, encoding: .utf8)
        let alphaCSSBefore = try alphaCSSContents(alphaResult)

        _ = try await ExportService.exportHTML(
            ExportRequest(
                text: "# Beta\n\n![b](beta.png)\n",
                sourceGeneration: 1,
                theme: BundledThemes.dark,
                documentURL: directory.appendingPathComponent("Beta.md"),
                resourceAccess: ExportResourceAccess(openingDirectory: directory)
            ),
            to: .html(url: betaURL, mode: .standalone(style: .linked))
        )

        // Exporting Beta must not change one byte of Alpha's HTML or CSS.
        let alphaHTMLAfter = try String(contentsOf: alphaURL, encoding: .utf8)
        #expect(alphaHTMLAfter == alphaHTMLBefore)
        let alphaCSSAfter = try alphaCSSContents(alphaResult)
        #expect(alphaCSSAfter == alphaCSSBefore)

        // Each document's own directory holds only its own resources: the
        // marker, its one image, and its linked stylesheet — three files, with
        // different content-addressed names between Alpha and Beta because the
        // image bytes and the theme-derived stylesheet both differ.
        let alphaAssetsDir = directory.appendingPathComponent(alphaAssetsDirName)
        let betaAssetsDir = directory.appendingPathComponent(betaAssetsDirName)
        let alphaFiles = try Set(FileManager.default.contentsOfDirectory(atPath: alphaAssetsDir.path))
        let betaFiles = try Set(FileManager.default.contentsOfDirectory(atPath: betaAssetsDir.path))
        #expect(alphaFiles.count == 3)
        #expect(betaFiles.count == 3)
        let alphaOwnResources = alphaFiles.subtracting([ExportFileWriter.markerFileName])
        let betaOwnResources = betaFiles.subtracting([ExportFileWriter.markerFileName])
        #expect(alphaOwnResources.isDisjoint(with: betaOwnResources))
    }

    private func alphaCSSContents(_ result: ExportResult) throws -> Data {
        let cssURL = try #require(result.companionFiles.first { $0.pathExtension == "css" })
        return try Data(contentsOf: cssURL)
    }
}
