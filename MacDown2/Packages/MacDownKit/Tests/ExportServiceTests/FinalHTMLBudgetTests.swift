@testable import ExportService
import Foundation
import Testing

struct FinalHTMLBudgetTests {
    private func prepared(
        body: String = "<p>é😀</p>", title: String = "A & <B>",
        visibleTitle: String? = "\u{0600}<\u{0301}", css: String = "body { color: black; }",
        directory: String = "report.assets", resources: [ExportResource] = []
    ) -> PreparedExportDocument {
        PreparedExportDocument(
            title: title, visibleTitle: visibleTitle, bodyHTML: body, assetsDirectoryName: directory,
            stylesheet: css, manifest: ExportManifest(resources: resources, referenceMap: [:]),
            diagnostics: [], sourceGeneration: 1, preservesRawHTML: false
        )
    }

    private func resource() -> ExportResource {
        let bytes = Data(repeating: 0x41, count: 96)
        return ExportResource(identity: ExportResourceIdentity(bytes: bytes, mimeType: "image/png"), bytes: bytes)
    }

    private func expectBudget(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected final HTML budget rejection")
        } catch ExportError.budgetExceeded {
            // Expected policy rejection.
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test func normalOutputRetainsExactTemplateBytes() throws {
        let input = prepared()
        let head = "<meta name=\"example\" content=\"yes\">"
        let expected = BuiltInExportTemplate.document(
            title: input.title, visibleTitle: input.visibleTitle, headExtras: head,
            styleElement: "<style>\n\(input.stylesheet)\n</style>", body: input.bodyHTML
        )
        #expect(try ExportHTMLWriter.selfContainedHTML(from: input, additionalHead: head) == expected)
        #expect(try ExportHTMLWriter.companionHTML(from: input, style: .embedded, additionalHead: head) == expected)
    }

    @Test(arguments: [ExportStyleEmbedding.embedded, .linked])
    func companionBoundaryUsesCompleteUTF8Bytes(style: ExportStyleEmbedding) throws {
        let input = prepared()
        let head = "<!-- policy -->"
        let html = try ExportHTMLWriter.companionHTML(from: input, style: style, additionalHead: head)
        let size = html.utf8.count
        #expect(size > html.count)
        expectBudget {
            _ = try ExportHTMLWriter.companionHTML(from: input, style: style, additionalHead: head, limit: size - 1)
        }
        #expect(try ExportHTMLWriter.companionHTML(from: input, style: style,
                                                   additionalHead: head, limit: size) == html)
        #expect(try ExportHTMLWriter.companionHTML(from: input, style: style,
                                                   additionalHead: head, limit: size + 1) == html)
    }

    @Test func repeatedResourceOccurrencesAreChargedIndividually() throws {
        let image = resource()
        let reference = "<img src=\"report.assets/\(image.identity.fileName)\">"
        let input = prepared(body: String(repeating: reference, count: 12), resources: [image])
        let html = try ExportHTMLWriter.selfContainedHTML(from: input)
        let uri = "data:image/png;base64," + image.bytes.base64EncodedString()
        #expect(html.components(separatedBy: uri).count == 13)
        let size = html.utf8.count
        expectBudget { _ = try ExportHTMLWriter.selfContainedHTML(from: input, limit: size - 1) }
        #expect(try ExportHTMLWriter.selfContainedHTML(from: input, limit: size) == html)
        #expect(try ExportHTMLWriter.selfContainedHTML(from: input, limit: size + 1) == html)
        // Resource deduplication must not charge a large image only once.
        expectBudget { _ = try ExportHTMLWriter.selfContainedHTML(from: input, limit: size - uri.utf8.count) }
    }

    @Test func rawEncodedAndCmarkEscapedReferencesStillEmbed() throws {
        let image = resource()
        let directory = "é & ' report.assets"
        let references = ExportHTMLWriter.referenceForms(of: directory).map {
            "<img src=\"\($0)/\(image.identity.fileName)\">"
        }.joined()
        let input = prepared(body: references, directory: directory, resources: [image])
        let html = try ExportHTMLWriter.selfContainedHTML(from: input)
        #expect(html.components(separatedBy: "data:image/png;base64,").count == 4)
        #expect(!html.contains(image.identity.fileName))
    }

    @Test func unusedResourceDoesNotAllocateOrChargeBase64() throws {
        let input = prepared(resources: [resource()])
        let without = prepared()
        let html = try ExportHTMLWriter.selfContainedHTML(from: without)
        #expect(try ExportHTMLWriter.selfContainedHTML(from: input, limit: html.utf8.count) == html)
    }

    @Test func escapedMetadataStylesAndHeadAreIncluded() throws {
        let baseline = try ExportHTMLWriter.selfContainedHTML(from: prepared())
        let cap = baseline.utf8.count
        let inputs = [
            prepared(title: String(repeating: "&", count: cap)),
            prepared(visibleTitle: String(repeating: "<", count: cap)),
            prepared(css: String(repeating: "x", count: cap)),
        ]
        for input in inputs {
            expectBudget { _ = try ExportHTMLWriter.selfContainedHTML(from: input, limit: cap) }
        }
        expectBudget {
            _ = try ExportHTMLWriter.selfContainedHTML(
                from: prepared(),
                additionalHead: String(repeating: "x", count: cap),
                limit: cap
            )
        }
    }

    @Test func dataURISizingChecksRoundingAndIntegerOverflow() throws {
        for bytes in 0 ... 12 {
            let data = Data(repeating: 0, count: bytes)
            let actual = ("data:image/png;base64," + data.base64EncodedString()).utf8.count
            #expect(try BoundedExportHTML.dataURISize(payloadBytes: bytes, mimeBytes: 9) == actual)
        }
        for (payload, mime) in [(Int.max, 9), (Int.max - 2, 9), (1, Int.max), (-1, 9), (1, -1)] {
            expectBudget { _ = try BoundedExportHTML.dataURISize(payloadBytes: payload, mimeBytes: mime) }
        }
        var sink = BoundedExportHTML(limit: Int.max, measuring: true)
        try sink.appendCount(Int.max)
        expectBudget { try sink.append("x") }
    }

    @Test func countingPassIncludesClosingMarkupBeforeMaterializingBody() {
        let metadata = BuiltInExportTemplate.BoundedMetadata(title: "", visibleTitle: nil, headExtras: "")
        let html = BuiltInExportTemplate.document(title: "", styleElement: "", body: "body")
        var materialized = false
        expectBudget {
            _ = try BuiltInExportTemplate.boundedDocument(
                metadata: metadata, limit: html.utf8.count - 1, style: { _ in }, body: { sink in
                    if !sink.measuring {
                        materialized = true
                    }
                    try sink.append("body")
                }
            )
        }
        #expect(!materialized)
    }

    @Test func repeatedFalsePrefixesPreserveBytesWithoutEmbedding() throws {
        let body = String(repeating: "<p>report.assets/missing.png</p>", count: 10000)
        let input = prepared(body: body, resources: [resource()])
        let html = try ExportHTMLWriter.selfContainedHTML(from: input)
        #expect(html.contains(body))
        #expect(!html.contains("data:image/png"))
    }

    @Test func cancellationRejectsBothOutputShapes() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let input = prepared(resources: [resource()])
            for operation in [
                { try ExportHTMLWriter.selfContainedHTML(from: input) },
                { try ExportHTMLWriter.companionHTML(from: input, style: .linked) },
            ] {
                do {
                    _ = try operation()
                    Issue.record("Cancelled assembly succeeded")
                } catch is CancellationError {
                    // Cancellation must keep its identity.
                } catch {
                    Issue.record("Wrong cancellation error: \(error)")
                }
            }
        }
        await task.value
    }

    @Test(arguments: [HTMLExportMode.selfContained, .standalone(style: .embedded), .standalone(style: .linked)])
    func rejectionLeavesExistingPrimaryAndSidecarsUntouched(mode: HTMLExportMode) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let primary = root.appendingPathComponent("report.html")
        let assets = root.appendingPathComponent("report.assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("previous primary".utf8).write(to: primary)
        let marker = assets.appendingPathComponent(ExportFileWriter.markerFileName)
        try Data("untrusted marker".utf8).write(to: marker)
        let user = assets.appendingPathComponent("user.txt")
        try Data("untouched".utf8).write(to: user)
        expectBudget {
            _ = try ExportFileWriter.writeHTML(prepared(resources: [resource()]),
                                               to: .html(url: primary, mode: mode), limit: 32)
        }
        #expect(try String(contentsOf: primary, encoding: .utf8) == "previous primary")
        #expect(try String(contentsOf: marker, encoding: .utf8) == "untrusted marker")
        #expect(try String(contentsOf: user, encoding: .utf8) == "untouched")
        #expect(try FileManager.default.contentsOfDirectory(atPath: assets.path).count == 2)
        let absent = root.appendingPathComponent("absent/new.html")
        expectBudget {
            _ = try ExportFileWriter.writeHTML(prepared(), to: .html(url: absent, mode: mode), limit: 32)
        }
        #expect(!FileManager.default.fileExists(atPath: absent.deletingLastPathComponent().path))
    }
}
