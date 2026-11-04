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
        try ExportTestSupport.writeFixture(named: "image.png", in: directory, bytes: Data([0x89, 0x50, 0x4E]))
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
}
