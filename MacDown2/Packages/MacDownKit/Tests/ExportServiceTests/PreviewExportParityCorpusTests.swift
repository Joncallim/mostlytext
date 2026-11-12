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

    private func surfaces(
        _ source: String,
        contributions: [ExportDerivedContribution] = []
    ) async throws -> Surfaces {
        let document = try await ParseEngine().parse(source, revision: 1)
        let blocks = PreviewBlock.blocks(from: document, text: source)
        let export = try await ExportService.prepare(
            ExportRequest(
                text: source, sourceGeneration: 1,
                theme: ExportTestSupport.lightTheme(), contributions: contributions
            ),
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

    @Test func nonOneOrderedListStartsSurviveTopLevelAndQuotedSource() async throws {
        let source = "4. first\n5. 東京\n\n> 7. quoted\n> 8. later\n"
        let result = try await surfaces(source)
        #expect(result.blocks.map(\.kind) == [.orderedList(startIndex: 4), .blockQuote])
        let list = try #require(result.blocks.first)
        #expect(list.source == "4. first\n5. 東京")
        #expect(list.lineRange == 1 ... 2)
        let listPreview = try rendered(list)
        #expect(containsIntent(listPreview) {
            if case .orderedList = $0 {
                true
            } else {
                false
            }
        })
        let listText = String(listPreview.characters)
        let first = try #require(listText.range(of: "first"))
        let second = try #require(listText.range(of: "東京"))
        #expect(first.lowerBound < second.lowerBound)

        let quote = try #require(result.blocks.last)
        #expect(quote.source == "> 7. quoted\n> 8. later")
        #expect(result.document.blocks.last?.children.first?.kind == .orderedList(startIndex: 7))
        let quotePreview = try rendered(quote)
        #expect(containsIntent(quotePreview) { $0 == .blockQuote })
        #expect(containsIntent(quotePreview) {
            if case .orderedList = $0 {
                true
            } else {
                false
            }
        })

        let html = result.export.bodyHTML
        #expect(html.contains("<ol start=\"4\">"))
        #expect(html.contains("<ol start=\"7\">"))
        #expect(html.contains("東京"))
        #expect(html.contains("<blockquote>"))
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

    @Test func inlineMathKeepsTheSameAuthoredRangeAcrossNativeAndStaticSurfaces() async throws {
        let source = "Before $x^2$ after.\n"
        let math = "$x^2$"
        let range = (source as NSString).range(of: math)
        let contribution = ExportDerivedContribution(
            sourceRange: range.location ..< NSMaxRange(range), placement: .inline,
            html: "<span class=\"math\">x²</span>", sourceGeneration: 1
        )
        let result = try await surfaces(source, contributions: [contribution])
        let block = try #require(result.blocks.first)
        #expect(block.source == "Before $x^2$ after.")
        let native = try PreviewMarkupParser(syntaxExtensions: [.math]).attributedString(for: block.source)
        #expect(String(native.characters) == "Before \u{FFFC} after.")
        #expect(result.export.bodyHTML.contains("<p>Before <span class=\"math\">x²</span> after.</p>"))
        #expect(!result.export.bodyHTML.contains("$x^2$"))
    }

    @Test(arguments: ["mermaid", "d2", "dot"])
    func diagramFencesKeepTheirSourceAndPlaceOneStaticContribution(language: String) async throws {
        let fence = "```\(language)\nA -> B\n```"
        let source = "Intro\n\n\(fence)\n\nOutro\n"
        let range = (source as NSString).range(of: fence)
        let contribution = ExportDerivedContribution(
            sourceRange: range.location ..< NSMaxRange(range), placement: .block,
            html: "<figure>\(language) rendered</figure>", sourceGeneration: 1
        )
        let result = try await surfaces(source, contributions: [contribution])
        #expect(result.blocks.map(\.kind) == [
            .paragraph, .codeBlock(language: language), .paragraph,
        ])
        #expect(result.blocks[1].source == fence)
        #expect(result.export.bodyHTML.contains("<p>Intro</p>"))
        #expect(result.export.bodyHTML.contains("<figure>\(language) rendered</figure>"))
        #expect(result.export.bodyHTML.contains("<p>Outro</p>"))
        #expect(!result.export.bodyHTML.contains("A -&gt; B"))

        let failed = ExportDerivedContribution(
            sourceRange: range.location ..< NSMaxRange(range), placement: .block,
            html: "<figure>broken</figure>", sourceGeneration: 1,
            diagnostics: [.init(severity: .error, message: "renderer unavailable")]
        )
        let fallback = try await surfaces(source, contributions: [failed])
        #expect(fallback.blocks[1].source == fence)
        #expect(fallback.export.bodyHTML.contains("A -&gt; B"))
        #expect(!fallback.export.bodyHTML.contains("<figure>broken</figure>"))
    }
}

extension PreviewExportParityCorpusTests {
    @Test func inlineLinkAndImageTargetsAgreeAcrossPreviewAndExport() async throws {
        let source = "See [site](https://example.com/a?q=1&x=2) and ![alt](https://example.com/a.png).\n"
        let result = try await surfaces(source)
        let block = try #require(result.blocks.first)
        #expect(result.blocks.count == 1)
        #expect(block.source == String(source.dropLast()))
        let preview = try rendered(block)
        #expect(String(preview.characters) == "See site and alt.")
        #expect(preview.runs.compactMap(\.link).map(\.absoluteString) == ["https://example.com/a?q=1&x=2"])
        #expect(preview.runs.compactMap(\.imageURL).map(\.absoluteString) == ["https://example.com/a.png"])
        #expect(result.export.bodyHTML ==
            "<p>See <a href=\"https://example.com/a?q=1&amp;x=2\">site</a> " +
            "and <img src=\"https://example.com/a.png\" alt=\"alt\" />.</p>\n")
    }

    @Test func footnoteSyntaxRemainsLiteralOnBothCurrentRenderers() async throws {
        let source = "Text[^note].\n\n[^note]: Footnote body.\n"
        let result = try await surfaces(source)
        // Neither current renderer enables a footnote extension. The source
        // remains visible instead of one path silently consuming a definition.
        #expect(result.blocks.map(\.kind) == [.paragraph, .paragraph])
        #expect(result.blocks.map(\.source) == ["Text[^note].", "[^note]: Footnote body."])
        let renderedBlocks = try result.blocks.map { try String(rendered($0).characters) }
        #expect(renderedBlocks == ["Text[^note].", "[^note]: Footnote body."])
        #expect(result.export.bodyHTML == "<p>Text[^note].</p>\n<p>[^note]: Footnote body.</p>\n")
    }

    @Test func duplicateReferenceDefinitionsResolveToTheFirstTargetOnBothPaths() async throws {
        let source = """
        Read [the guide][docs] and [again][docs].

        [docs]: https://example.com/guide "Guide"
        [docs]: https://example.com/other "Other"

        """
        let result = try await surfaces(source)
        let block = try #require(result.blocks.first)
        let facts = try #require(result.document.sourceFacts)
        let anchor = try #require(block.sourceAnchor)
        let prefix = try MarkdownReferenceReplayIndex(facts: facts).prefix(
            for: anchor.range, sourceSHA256: anchor.sourceSHA256,
            maximumUTF8Bytes: PreviewParserBudget.maximumUTF8Bytes
        )
        #expect(prefix.contains("[docs]: https://example.com/guide"))
        #expect(!prefix.contains("https://example.com/other"))
        let preview = try PreviewMarkupParser().attributedString(for: prefix + block.source)
        #expect(preview.runs.compactMap(\.link).map(\.absoluteString) == [
            "https://example.com/guide", "https://example.com/guide",
        ])
        #expect(result.export.bodyHTML.contains("href=\"https://example.com/guide\""))
        #expect(!result.export.bodyHTML.contains("https://example.com/other"))
    }

    @Test func tagfilterAndDangerousLinkPolicyAreDeliberateExportDifferences() async throws {
        let source = "<script>alert(1)</script>\n\n[unsafe](javascript:alert%281%29)\n"
        let result = try await surfaces(source)
        #expect(result.blocks.count == 2)
        let rawPreview = try rendered(#require(result.blocks.first))
        #expect(String(rawPreview.characters).contains("<script>alert(1)</script>"))
        let linkPreview = try rendered(#require(result.blocks.last))
        #expect(String(linkPreview.characters).contains("unsafe"))
        let html = result.export.bodyHTML
        #expect(!html.contains("<script>"))
        #expect(!html.contains("href=\"javascript:"))
        #expect(html.contains("unsafe"))
    }
}
