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

    @Test func pendingSourceHasNoURLAuthorityButKeepsOrdinaryNativeFormatting() throws {
        let parser = PreviewPendingMarkupParser(baseURL: nil)
        for source in ["[link](/target)", "![image](/private.png)", "<https://example.com>"] {
            let parsed = try parser.attributedString(for: source)
            #expect(String(parsed.characters).utf8.elementsEqual(source.utf8))
            #expect(parsed.runs.allSatisfy { $0.link == nil && $0.imageURL == nil })
        }
        let plain = try parser.attributedString(for: "**ordinary**")
        #expect(String(plain.characters) == "ordinary")
        #expect(plain.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test func generatedAndCodeBlocksDoNotBecomeMathPendingSource() {
        let generated = PreviewBlock(kind: .paragraph, source: "$a_b$", lineRange: 1 ... 1)
        let code = PreviewBlock(
            kind: .codeBlock(language: "mermaid"),
            source: "```mermaid\nA[$5]\n```",
            lineRange: 1 ... 3
        )
        let generatedLiteral = BlockView.showsLiteralSource(block: generated, mathContent: .pending)
        let codeLiteral = BlockView.showsLiteralSource(block: code, mathContent: .pending)
        #expect(!generatedLiteral && !codeLiteral)
    }

    @Test func droppingAuthorityForcesFreshNativeSourceFallbackEvenWhenMarkdownIsUnchanged() throws {
        let source = "[one][key] and [two][key]"
        let prefix = "[key]: /same\n\n"
        let first = PreviewMathInput.Reference(range: 0 ..< 10, destination: "/same", kind: .link)
        let second = PreviewMathInput.Reference(range: 15 ..< 25, destination: "/same", kind: .link)
        let full = try PreviewMathInput(source: source, prefix: prefix, replacements: [], references: [first, second])
        let reduced = try PreviewMathInput(source: source, prefix: prefix, replacements: [], references: [first])
        let admitted = try PreviewMathMarkupParser(input: full, attachments: [:]).attributedString(for: source)
        #expect(admitted.runs.contains { $0.link?.relativeString == "/same" })
        let rejected = try PreviewMathMarkupParser(input: reduced, attachments: [:]).attributedString(for: source)
        #expect(String(rejected.characters).utf8.elementsEqual(source.utf8))
        #expect(rejected.runs.allSatisfy { $0.link == nil })
    }
}
