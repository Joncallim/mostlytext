@testable import Preview
import Testing

@Suite("PreviewBlock oversize guard")
struct PreviewBlockOversizeTests {
    @Test func typicalBlockIsNotOversize() {
        let block = PreviewBlock(kind: .paragraph, source: "Just a normal paragraph.", lineRange: 1 ... 1)
        #expect(block.isOversize == false)
    }

    @Test func blockAtExactlyTheThresholdIsNotOversize() {
        let source = String(repeating: "a", count: PreviewBlock.oversizeByteThreshold)
        let block = PreviewBlock(kind: .codeBlock(language: nil), source: source, lineRange: 1 ... 1)
        #expect(source.utf8.count == PreviewBlock.oversizeByteThreshold)
        #expect(block.isOversize == false)
    }

    @Test func blockOneByteOverTheThresholdIsOversize() {
        let source = String(repeating: "a", count: PreviewBlock.oversizeByteThreshold + 1)
        let block = PreviewBlock(kind: .codeBlock(language: nil), source: source, lineRange: 1 ... 1)
        #expect(block.isOversize == true)
    }

    // Regression: a single oversize code fence should degrade on its own,
    // without any other block in the document being affected — this is the
    // scenario a large pasted log or minified bundle produces.
    @Test func oversizeGuardIsPerBlockNotPerDocument() {
        let normal = PreviewBlock(kind: .paragraph, source: "short", lineRange: 1 ... 1)
        let big = PreviewBlock(
            kind: .codeBlock(language: "text"),
            source: String(repeating: "x", count: PreviewBlock.oversizeByteThreshold * 2),
            lineRange: 3 ... 3
        )
        #expect(normal.isOversize == false)
        #expect(big.isOversize == true)
    }
}

@Suite("PreviewLinkDefinitions")
struct PreviewLinkDefinitionsTests {
    @Test func extractsSingleLineDefinition() {
        let text = "See [my link][ref] for details.\n\n[ref]: https://example.com \"Example\"\n"
        let definitions = PreviewLinkDefinitions.extract(from: text)
        #expect(definitions == ["[ref]: https://example.com \"Example\""])
    }

    @Test func extractsMultipleDefinitionsInDocumentOrder() {
        let text = """
        [one]: https://example.com/one
        Some paragraph text in between.
        [two]: https://example.com/two "Two"
        """
        let definitions = PreviewLinkDefinitions.extract(from: text)
        #expect(definitions == [
            "[one]: https://example.com/one",
            "[two]: https://example.com/two \"Two\"",
        ])
    }

    @Test func ignoresNonDefinitionLines() {
        let text = """
        # Heading
        A paragraph that mentions [a link](https://example.com) inline.
        - a list item
        > a blockquote
        """
        #expect(PreviewLinkDefinitions.extract(from: text).isEmpty)
    }

    @Test func allowsUpToThreeLeadingSpaces() {
        let text = "   [ref]: https://example.com"
        #expect(PreviewLinkDefinitions.extract(from: text) == ["   [ref]: https://example.com"])
    }

    @Test func fourLeadingSpacesIsNotADefinition() {
        // Four spaces is CommonMark's indented-code-block threshold, which
        // takes priority over a reference definition.
        let text = "    [ref]: https://example.com"
        #expect(PreviewLinkDefinitions.extract(from: text).isEmpty)
    }

    @Test func emptyTextReturnsNoDefinitions() {
        #expect(PreviewLinkDefinitions.extract(from: "").isEmpty)
    }

    // The remaining tests exercise edge cases found while replacing the
    // original `Regex`-based scan with a hand-rolled `unichar` scan for
    // speed (~30x faster on a 1 MB document) — each was verified to behave
    // identically to the `Regex` version before the swap.

    @Test func emptyLabelIsNotADefinition() {
        #expect(PreviewLinkDefinitions.extract(from: "[]: https://example.com").isEmpty)
    }

    @Test func missingSpaceAfterColonIsNotADefinition() {
        #expect(PreviewLinkDefinitions.extract(from: "[ref]:https://example.com").isEmpty)
    }

    @Test func missingDestinationIsNotADefinition() {
        #expect(PreviewLinkDefinitions.extract(from: "[ref]: ").isEmpty)
        #expect(PreviewLinkDefinitions.extract(from: "[ref]:  ").isEmpty)
    }

    @Test func unterminatedBracketIsNotADefinition() {
        #expect(PreviewLinkDefinitions.extract(from: "[unterminated bracket: https://example.com").isEmpty)
    }

    @Test func missingOpeningBracketIsNotADefinition() {
        #expect(PreviewLinkDefinitions.extract(from: "]: https://example.com").isEmpty)
    }

    @Test func tabsAreAcceptedAsTheSeparator() {
        let text = "[ref]:\t\thttps://example.com"
        #expect(PreviewLinkDefinitions.extract(from: text) == [text])
    }

    @Test func mixedSpacesAndTabsAreAcceptedAsTheSeparator() {
        let text = "[ref]:  \t https://example.com"
        #expect(PreviewLinkDefinitions.extract(from: text) == [text])
    }

    /// A non-breaking space is Unicode whitespace but not the literal ASCII
    /// space/tab the separator scan matches; landing immediately after the
    /// colon it must not count as the start of a destination.
    @Test func nonBreakingSpaceAfterColonIsNotADefinition() {
        let text = "[ref]: \u{00A0}https://example.com"
        #expect(PreviewLinkDefinitions.extract(from: text).isEmpty)
    }

    @Test func nestedBracketLikeLabelStopsAtFirstCloseBracket() {
        // Matches the original Regex's `[^\]\n]+` semantics: the label is
        // everything up to the first ']', not brace-matched.
        let text = "[a[b]]: https://example.com"
        #expect(PreviewLinkDefinitions.extract(from: text).isEmpty)
    }

    @Test func aFootnoteDefinitionIsNotALinkDefinition() {
        #expect(PreviewLinkDefinitions.extract(from: "[^1]: Footnote text goes here.").isEmpty)
    }

    @Test func freeTextAfterTheDestinationIsNotADefinition() {
        #expect(PreviewLinkDefinitions.extract(from: "[Note]: this is a remark").isEmpty)
    }

    @Test func titlesInQuotesAndParenthesesAreStillDefinitions() {
        let lines = ["[a]: https://e.com \"Title\"", "[b]: <https://e.com> 'Title'", "[c]: /x (Title)", "[d]: /x"]

        #expect(PreviewLinkDefinitions.extract(from: lines.joined(separator: "\n")) == lines)
    }

    @Test func anUnterminatedTitleIsNotADefinition() {
        #expect(PreviewLinkDefinitions.extract(from: "[a]: /x \"Title").isEmpty)
    }

    /// `extract` split on `\n` only, so in a CRLF document every definition line ended in `\r`, which the new
    /// destination/title validation read as free text: no definition was ever found.
    @Test func definitionsInACRLFDocumentAreFound() {
        let text = "[a]: /url\r\n\r\n[b]: /other \"Title\"\r\ntext [a]\r\n"

        #expect(PreviewLinkDefinitions.extract(from: text) == ["[a]: /url", "[b]: /other \"Title\""])
    }

    @Test func definitionsInACROnlyDocumentAreFound() {
        let text = "[a]: /url\r\r[b]: /other \"Title\"\rtext [a]\r"

        #expect(PreviewLinkDefinitions.extract(from: text) == ["[a]: /url", "[b]: /other \"Title\""])
    }

    @Test func definitionsInAMixedLineEndingDocumentAreFound() {
        let text = "[a]: /url\r[b]: /other\n[c]: /third\r\ntext [a]\r"

        #expect(PreviewLinkDefinitions.extract(from: text) == ["[a]: /url", "[b]: /other", "[c]: /third"])
    }
}
