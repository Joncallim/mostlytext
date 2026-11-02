@testable import ExportService
import Foundation
import Testing

struct ExportResourceSlotTests {
    private func resource() -> ExportResource {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        return ExportResource(identity: ExportResourceIdentity(bytes: data, mimeType: "image/png"), bytes: data)
    }

    private func document(_ markdown: String, directory: String = "report.assets") throws -> PreparedExportDocument {
        let image = resource()
        let registry = ExportResourceURLRegistry(avoiding: [markdown, directory], assetsDirectoryName: directory)
        let rendered = try CMarkGFM.render(markdown, options: CMarkGFM.optUnsafe) { _, isImage in
            try isImage ? .rewrite(registry.register(image.identity)) : .keep
        }
        let output = try registry.resolve(rendered.html)
        return PreparedExportDocument(
            title: "", bodyHTML: output.html, assetsDirectoryName: directory, stylesheet: "",
            manifest: ExportManifest(resources: [image], referenceMap: [:]), diagnostics: [],
            sourceGeneration: 1, preservesRawHTML: true
        ).registeringResourceSlots(output.slots)
    }

    @Test func authoredLookalikePathsAreNeverEmbedded() throws {
        let path = "report.assets/" + resource().identity.fileName
        let markdown = """
        ![generated](a.png)

        Literal \(path)

        `\(path)`

        ```html
        <img src="\(path)">
        ```

        [navigation](\(path))

        <img src="\(path)" alt="authored">
        """
        let input = try document(markdown)
        let html = try ExportHTMLWriter.selfContainedHTML(from: input)
        #expect(html.components(separatedBy: "data:image/png;base64,").count == 2)
        #expect(html.contains("Literal " + path))
        #expect(html.contains("<code>" + path + "</code>"))
        #expect(html.contains("href=\"" + path + "\""))
        #expect(html.contains("src=\"" + path + "\" alt=\"authored\""))
        #expect(input.resourceSlots?.occurrences.count == 1)
        #expect(!html.contains("MTRESOURCE"))
    }

    @Test func repeatedGeneratedImagesShareBytesButOwnSeparateSlots() throws {
        let input = try document("![a](a.png) ![b](a.png)\n\n| image |\n| --- |\n| ![c](a.png) |")
        #expect(input.resourceSlots?.occurrences.count == 3)
        let html = try ExportHTMLWriter.selfContainedHTML(from: input)
        #expect(html.components(separatedBy: "data:image/png;base64,").count == 4)
    }

    @Test func imageDescriptionsDoNotRegisterUnemittedImageOrLinkURLs() throws {
        let input = try document("![![inner](b.png) [link](other.png)](a.png)")
        #expect(input.resourceSlots?.occurrences.count == 1)
        #expect(try ExportHTMLWriter.selfContainedHTML(from: input).contains("data:image/png;base64,"))
    }

    @Test func unicodeAndQuotedDestinationUsesSeparateURLAndHTMLRules() throws {
        let directory = "A & B \"é%#?\".assets"
        let input = try document("é😀 ![a](a.png)", directory: directory)
        let companion = try ExportHTMLWriter.companionHTML(from: input, style: .embedded)
        #expect(companion.contains("A%20%26%20B%20%22%C3%A9%25%23%3F%22.assets/"))
        #expect(!companion.contains(directory))
        #expect(try ExportHTMLWriter.selfContainedHTML(from: input).contains("é😀"))
    }

    @Test func publicPreparedInitializerDoesNotGrantSubstitutionAuthority() throws {
        let image = resource()
        let manual = PreparedExportDocument(
            title: "", bodyHTML: "<img src=\"report.assets/\(image.identity.fileName)\">", stylesheet: "",
            manifest: ExportManifest(resources: [image], referenceMap: [:]), diagnostics: [],
            sourceGeneration: 1, preservesRawHTML: true
        )
        #expect(throws: ExportError.self) { _ = try ExportHTMLWriter.selfContainedHTML(from: manual) }
        #expect(try ExportHTMLWriter.companionHTML(from: manual, style: .embedded).contains(manual.bodyHTML))
    }

    @Test func staleBodyOrMissingManifestIdentityRejectsBothAssemblyModes() throws {
        let input = try document("![a](a.png)")
        for (body, manifest) in [(input.bodyHTML + "x", input.manifest), (input.bodyHTML, ExportManifest.empty)] {
            let stale = PreparedExportDocument(
                title: "", bodyHTML: body, stylesheet: "", manifest: manifest, diagnostics: [],
                sourceGeneration: 1, preservesRawHTML: true
            ).registeringResourceSlots(input.resourceSlots)
            #expect(throws: ExportError.self) { _ = try ExportHTMLWriter.selfContainedHTML(from: stale) }
            #expect(throws: ExportError.self) { _ = try ExportHTMLWriter.companionHTML(from: stale, style: .embedded) }
        }
    }

    private static let rejectedContexts = [
        "<p>TOKEN</p>", "<!-- <img src=\"TOKEN\"> -->", "<div title='<img src=\"TOKEN\">'>x</div>",
        "<style> a < b; <img src=\"TOKEN\"></style>", "<textarea><img src=\"TOKEN\"></textarea>",
        "<![CDATA[><img src=\"TOKEN\">]]>",
        "<img src=\"TOKEN\"><img src=\"TOKEN\">", "<img src=TOKEN>", "<img title=\"TOKEN\">", "",
    ]

    @Test(arguments: ExportResourceSlotTests.rejectedContexts)
    func misplacedMissingOrDuplicateTokenFailsClosed(template: String) throws {
        let registry = ExportResourceURLRegistry(avoiding: [], assetsDirectoryName: "report.assets")
        let token = try registry.register(resource().identity)
        let html = template.replacingOccurrences(of: "TOKEN", with: token)
        #expect(throws: ExportError.self) { _ = try registry.resolve(html) }
    }

    @Test func scannerSkipsQuotedMarkupCommentsAndRawTextBeforeGeneratedImage() throws {
        let registry = ExportResourceURLRegistry(avoiding: [], assetsDirectoryName: "report.assets")
        let token = try registry.register(resource().identity)
        let html = "<div title='<img src=\"not-a-slot\">'></div><!-->text<!-- --!>"
            + "<style>a < b; fake <img src=\"fake\"></style><img src=\"\(token)\">"
        let result = try registry.resolve(html)
        #expect(result.slots.occurrences.count == 1)
    }

    @Test func unresolvedNamespaceOutsideRegisteredAttributeIsRejected() throws {
        let registry = ExportResourceURLRegistry(avoiding: [], assetsDirectoryName: "report.assets")
        let token = try registry.register(resource().identity)
        #expect(throws: ExportError.self) { _ = try registry.resolve("<img src=\"\(token)\"><code>\(token)</code>") }
    }

    @Test func occurrenceQuotaAbortsTheCmarkWalkBeforeRendering() throws {
        let registry = ExportResourceURLRegistry(avoiding: [], assetsDirectoryName: "report.assets", maxOccurrences: 2)
        let identity = resource().identity
        #expect(throws: ExportError.self) {
            _ = try CMarkGFM.renderHTML("![a](a.png) ![b](a.png) ![c](a.png)", options: CMarkGFM.optDefault) { _, _ in
                try .rewrite(registry.register(identity))
            }
        }
    }

    @Test func preparedOutputIsDeterministicAcrossOpaqueNamespaces() throws {
        #expect(try document("![a](a.png) é") == document("![a](a.png) é"))
    }
}
