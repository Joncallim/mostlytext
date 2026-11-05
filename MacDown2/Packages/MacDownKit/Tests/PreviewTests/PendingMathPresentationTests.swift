import Foundation
@testable import Preview
import Testing

@MainActor
struct PendingMathPresentationTests {
    @Test func pendingDollarSourceAndExplicitRefusalNeverEnterAnotherMarkdownMathPass() throws {
        let block = PreviewBlock(kind: .paragraph, source: "$a_b$ and $\\frac{1}{$", lineRange: 1 ... 1)
        #expect(BlockView.showsLiteralSource(block: block, mathContent: nil))
        let refused = BlockView.showsLiteralSource(block: block, mathContent: .init(blocks: [block.id: .literal]))
        #expect(refused)
        let input = try PreviewMathInput(source: block.source, replacements: [])
        let prepared = BlockView.showsLiteralSource(
            block: block,
            mathContent: .init(blocks: [block.id: .parsed(input)])
        )
        #expect(!prepared)
    }

    @Test func ordinaryAndGeneratedContentKeepMarkdownButDefaultParserHasNoDollarExtension() throws {
        let plain = PreviewBlock(kind: .paragraph, source: "**ordinary**", lineRange: 1 ... 1)
        #expect(!BlockView.showsLiteralSource(block: plain, mathContent: nil))
        let generated = PreviewBlock(kind: .paragraph, source: "$a_b$", lineRange: 1 ... 1)
        #expect(generated.sourceAnchor == nil)
        let ordinary = BlockView.showsLiteralSource(block: generated, mathContent: .init(blocks: [:]))
        #expect(!ordinary)
        #expect(PreviewMarkupParser().syntaxExtensions.isEmpty)
        let parsed = try PreviewMarkupParser().attributedString(for: "$a+b$")
        #expect(String(parsed.characters) == "$a+b$")
        #expect(parsed.runs.allSatisfy { $0.textual.attachment == nil })
    }
}
