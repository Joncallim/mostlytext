@testable import ExportService
import Foundation
import Testing

struct ExportCompanionReferenceTests {
    private static let target = ExportTarget.html(
        url: URL(fileURLWithPath: "/tmp/reference-proof.html"), mode: .standalone(style: .embedded)
    )

    @Test(arguments: [
        "# Plain\n\nText and `old.assets/image.png`.\n",
        "[anchor](#section)\n\n[web](https://example.invalid/path)\n",
        "[mail](mailto:reader@example.invalid)\n",
        "[removed](javascript:alert(1))\n",
        "![inline](data:image/png;base64,iVBORw0KGgo=)\n",
    ])
    func composerCertifiesClosedGeneratedReferences(_ source: String) async throws {
        let prepared = try await ExportService.prepare(
            ExportRequest(text: source, sourceGeneration: 1, theme: ExportTestSupport.lightTheme()),
            target: Self.target
        )
        #expect(prepared.companionReferencesKnown)
        #expect(prepared.hasClosedCompanionReferences(for: source))
        #expect(!prepared.hasClosedCompanionReferences(for: source + "\n"))
    }

    @Test(arguments: [
        "[old resource](reference-proof.assets/old.png)\n",
        "[query](?asset=old.png)\n",
        "[network path](//example.invalid/old.png)\n",
        "<img src=\"reference-proof.assets/old.png\">\n",
        "<div>Even non-resource raw HTML is conservative.</div>\n",
        "![missing](reference-proof.assets/old.png)\n",
        "![remote](https://example.invalid/old.png)\n",
    ])
    func keptAuthoredReferencesPreventRetirement(_ source: String) async throws {
        let prepared = try await ExportService.prepare(
            ExportRequest(text: source, sourceGeneration: 1, theme: ExportTestSupport.lightTheme()),
            target: Self.target
        )
        #expect(!prepared.companionReferencesKnown)
    }

    @Test func generatedLocalImageIsFullyRegistered() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(
            named: "image.png",
            in: directory,
            bytes: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "![image](image.png)", sourceGeneration: 1,
                          theme: ExportTestSupport.lightTheme(),
                          resourceAccess: ExportResourceAccess(openingDirectory: directory)),
            target: Self.target
        )
        #expect(prepared.manifest.resources.count == 1)
        #expect(prepared.companionReferencesKnown)
    }

    @Test func customDerivedHTMLCannotCertifyUnregisteredReferences() async throws {
        let source = "$x$\n"
        let contribution = ExportDerivedContribution(
            sourceRange: 0 ..< 3, placement: .inline,
            html: "<img src=\"reference-proof.assets/old.png\">", sourceGeneration: 1
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(text: source, sourceGeneration: 1, theme: ExportTestSupport.lightTheme(),
                          contributions: [contribution]), target: Self.target
        )
        #expect(prepared.bodyHTML.contains("reference-proof.assets/old.png"))
        #expect(!prepared.companionReferencesKnown)
    }

    @Test func publicPreparedHTMLAndCSSHaveNoReferenceAuthority() {
        let prepared = PreparedExportDocument(
            title: "manual", bodyHTML: "<p>Manual</p>",
            stylesheet: "body { background: url(reference-proof.assets/old.png) }",
            manifest: ExportManifest(resources: [], referenceMap: [:]), diagnostics: [],
            sourceGeneration: 1, preservesRawHTML: false
        )
        #expect(!prepared.companionReferencesKnown)
        #expect(!prepared.hasClosedCompanionReferences(for: "manual"))
    }

    @Test func aChangedStructuralStylesheetCannotCertifyClosedReferences() {
        let actual = ExportThemeStylesheet.structural
        #expect(ExportThemeStylesheet.hasClosedReferences(structuralCSS: actual))
        #expect(!ExportThemeStylesheet.hasClosedReferences(
            structuralCSS: actual + "\nbody { background: url(old.assets/retained.png) }"
        ))
        #expect(!ExportThemeStylesheet.hasClosedReferences(structuralCSS: ""))
    }

    @Test func anInlineSVGPayloadCannotBorrowARasterHeader() async throws {
        let svg = Data("<svg><image href=\"old.assets/retained.png\"/></svg>".utf8).base64EncodedString()
        let source = "![spoof](data:image/png;base64,\(svg))"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: source, sourceGeneration: 1, theme: ExportTestSupport.lightTheme()), target: Self.target
        )
        #expect(prepared.bodyHTML.contains(svg))
        #expect(!prepared.companionReferencesKnown)
    }

    @Test func rasterSignatureKnowledgeDoesNotClaimImageValidity() {
        #expect(ExportURLPolicy.hasClosedRasterReferences(Data([0xFF, 0xD8, 0xFF]), mimeType: "image/jpeg"))
        #expect(ExportURLPolicy.hasClosedRasterReferences(Data("GIF89a".utf8), mimeType: "image/gif"))
        #expect(ExportURLPolicy.hasClosedRasterReferences(Data("RIFF0000WEBP".utf8), mimeType: "image/webp"))
        #expect(!ExportURLPolicy.hasClosedRasterReferences(Data("<svg/>".utf8), mimeType: "image/png"))
        #expect(!ExportURLPolicy.hasClosedRasterReferences(Data("<svg/>".utf8), mimeType: "image/svg+xml"))
        #expect(!ExportURLPolicy.embeddedRasterReferencesAreClosed("data:image/png;base64,AAAA="))
    }
}
