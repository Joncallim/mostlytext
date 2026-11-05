import Foundation
@testable import Preview
import Testing

struct PendingMathPresentationTests {
    @Test func pendingDollarSourceAndExplicitRefusalNeverEnterAnotherMarkdownMathPass() throws {
        let block = PreviewBlock(kind: .paragraph, source: "$a_b$ and $\\frac{1}{$", lineRange: 1 ... 1)
        #expect(BlockView.showsLiteralSource(block: block, mathContent: nil))
        #expect(BlockView.showsLiteralSource(block: block, mathContent: .init(blocks: [block.id: .literal])))
        let input = try PreviewMathInput(source: block.source, replacements: [])
        #expect(!BlockView.showsLiteralSource(block: block, mathContent: .init(blocks: [block.id: .parsed(input)])))
    }

    @Test func ordinaryAndGeneratedContentKeepMarkdownButDefaultParserHasNoDollarExtension() throws {
        let plain = PreviewBlock(kind: .paragraph, source: "**ordinary**", lineRange: 1 ... 1)
        #expect(!BlockView.showsLiteralSource(block: plain, mathContent: nil))
        let generated = PreviewBlock(kind: .paragraph, source: "$a_b$", lineRange: 1 ... 1)
        #expect(generated.sourceAnchor == nil)
        #expect(!BlockView.showsLiteralSource(block: generated, mathContent: .init(blocks: [:])))
        #expect(PreviewMarkupParser().syntaxExtensions.isEmpty)
        let parsed = try PreviewMarkupParser().attributedString(for: "$a+b$")
        #expect(String(parsed.characters) == "$a+b$")
        #expect(parsed.runs.allSatisfy { $0.textual.attachment == nil })
    }
}
