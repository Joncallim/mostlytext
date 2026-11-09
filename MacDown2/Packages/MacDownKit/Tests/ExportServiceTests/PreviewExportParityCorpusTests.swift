import ExportService
import Foundation
import MarkdownEngine
import Preview
import Testing

/// Compares the source actually sliced for native Preview with the ordinary
/// HTML export of the same source. These are semantic checks, not visual or
/// derived-renderer acceptance.
@MainActor
struct PreviewExportParityCorpusTests {
    private struct Surfaces {
        let document: MarkdownDocument
        let blocks: [PreviewBlock]
        let export: PreparedExportDocument
    }

    private func surfaces(_ source: String) async throws -> Surfaces {
        let document = try await ParseEngine().parse(source, revision: 1)
        let blocks = PreviewBlock.blocks(from: document, text: source)
        let export = try await ExportService.prepare(
            ExportRequest(text: source, sourceGeneration: 1, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/parity-corpus.html"), mode: .standalone(style: .embedded))
        )
        return Surfaces(document: document, blocks: blocks, export: export)
    }

    private func rendered(_ block: PreviewBlock) throws -> AttributedString {
        try PreviewMarkupParser().attributedString(for: block.source)
    }

    private func containsIntent(
        _ value: AttributedString,
        where matches: (PresentationIntent.Kind) -> Bool
    ) -> Bool {
        value.runs.contains { run in
            run.presentationIntent?.components.contains { matches($0.kind) } == true
        }
    }

    @Test func gfmTableIsStructuralOnBothPaths() async throws {
        let source = "| name | count |\n| :--- | ---: |\n| Café | 2 |\n"
        let result = try await surfaces(source)
        let block = try #require(result.blocks.first)
        #expect(block.kind == .table(columnCount: 2))
        #expect(!block.isOversize)
        let preview = try rendered(block)
        #expect(containsIntent(preview) {
            if case .table = $0 {
                true
            } else {
                false
            }
        })
        #expect(String(preview.characters).contains("Café"))
        #expect(result.export.bodyHTML.contains("<table>"))
        #expect(result.export.bodyHTML.contains("<th"))
        #expect(result.export.bodyHTML.contains("<td"))
        #expect(result.export.bodyHTML.contains("Café"))
    }

    @Test func taskListsKeepItemOrderAndStateAtTheParseBoundary() async throws {
        let source = "- [x] done\n- [ ] later\n"
        let result = try await surfaces(source)
        let block = try #require(result.blocks.first)
        #expect(block.kind == .unorderedList)
        #expect(block.source == "- [x] done\n- [ ] later")
        #expect(block.sourceAnchor != nil)
        #expect(block.lineRange == 1 ... 2)
        #expect(block.isOversize == false)
        #expect(result.document.blocks.first?.children.map(\.kind) == [
            .listItem(taskState: .checked), .listItem(taskState: .unchecked),
        ])
        let preview = try rendered(block)
        #expect(containsIntent(preview) {
            if case .listItem = $0 {
                true
            } else {
                false
            }
        })
        let previewText = String(preview.characters)
        let previewDone = try #require(previewText.range(of: "done"))
        let previewLater = try #require(previewText.range(of: "later"))
        #expect(previewDone.lowerBound < previewLater.lowerBound)
        let exportedHTML = result.export.bodyHTML
        #expect(exportedHTML.contains("type=\"checkbox\""))
        #expect(exportedHTML.contains("checked"))
        let exportedDone = try #require(exportedHTML.range(of: "done"))
        let exportedLater = try #require(exportedHTML.range(of: "later"))
        #expect(exportedDone.lowerBound < exportedLater.lowerBound)
    }

    @Test func strikethroughAndAutolinkSurviveBothRenderers() async throws {
        let source = "Visit https://example.com and ~~retire~~ this.\n"
        let result = try await surfaces(source)
        let preview = try rendered(#require(result.blocks.first))
        #expect(preview.runs.contains { $0.link?.absoluteString == "https://example.com" })
        #expect(preview.runs.contains { $0.inlinePresentationIntent?.contains(.strikethrough) == true })
        #expect(result.export.bodyHTML.contains("href=\"https://example.com\""))
        #expect(result.export.bodyHTML.contains("<del>retire</del>"))
    }

    @Test func duplicateUnicodeHeadingsKeepPreviewNavigationAndExportText() async throws {
        let source = "# Café 東京\n\n# Café 東京\n"
        let result = try await surfaces(source)
        let index = try HeadingAnchorIndex(
            document: result.document, sourceText: source,
            documentID: "parity-corpus", recoveryEpoch: UUID(), sourceGeneration: 1, reservedIDs: []
        )
        #expect(index.headings.map(\.fragment) == ["café-東京", "café-東京-1"])
        #expect(result.blocks.map(\.kind) == [.heading(level: 1), .heading(level: 1)])
        for block in result.blocks {
            let preview = try rendered(block)
            #expect(containsIntent(preview) { $0 == .header(level: 1) })
            #expect(String(preview.characters) == "Café 東京")
        }
        #expect(result.export.bodyHTML.components(separatedBy: "<h1>").count == 3)
        #expect(result.export.bodyHTML.contains("Café 東京"))
    }

    @Test func frontMatterIsMetadataAndNotPreviewOrExportBody() async throws {
        let source = "---\ntitle: Parity Note\nauthor: A\n---\n# Body\n"
        let result = try await surfaces(source)
        #expect(result.document.frontMatter != nil)
        #expect(result.export.title == "Parity Note")
        #expect(result.blocks.count == 1)
        let block = try #require(result.blocks.first)
        #expect(block.source == "# Body")
        #expect(try String(rendered(block).characters) == "Body")
        #expect(!result.export.bodyHTML.contains("author: A"))
        #expect(result.export.bodyHTML.contains("<h1>Body</h1>"))
    }

    @Test func nestedQuoteAndFenceKeepTheirStructureAndLiteralCode() async throws {
        let source = "> - **parent**\n>   - child\n\n```swift\nlet word = \"東京\"\n```\n"
        let result = try await surfaces(source)
        #expect(result.blocks.map(\.kind) == [.blockQuote, .codeBlock(language: "swift")])
        let quote = try rendered(#require(result.blocks.first))
        #expect(containsIntent(quote) { $0 == .blockQuote })
        #expect(containsIntent(quote) {
            if case .listItem = $0 {
                true
            } else {
                false
            }
        })
        #expect(quote.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        let code = try rendered(#require(result.blocks.last))
        #expect(String(code.characters).contains("let word = \"東京\""))
        #expect(result.export.bodyHTML.contains("<blockquote>"))
        #expect(result.export.bodyHTML.contains("<strong>parent</strong>"))
        #expect(result.export.bodyHTML.contains("<pre>"))
        #expect(result.export.bodyHTML.contains("東京"))
    }

    @Test func ordinaryRawHTMLHasAnExplicitSurfaceDifference() async throws {
        let source = "<b>authored</b>\n"
        let result = try await surfaces(source)
        let preview = try rendered(#require(result.blocks.first))
        #expect(String(preview.characters) == "<b>authored</b>")
        #expect(result.export.preservesRawHTML)
        #expect(result.export.bodyHTML.contains("<b>authored</b>"))
    }
}
