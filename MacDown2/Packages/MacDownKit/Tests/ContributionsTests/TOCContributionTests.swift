@testable import Contributions
import Foundation
import MarkdownEngine
import Testing

@Suite("TOCContribution")
struct TOCContributionTests {
    // MARK: - findMarkers (lexical + semantic admission)

    private static func document(_ text: String) async throws -> MarkdownDocument {
        try await ParseEngine().parse(text, revision: 0)
    }

    @Test func findMarkersLocatesASingleMarkerLine() async throws {
        let text = "# Title\n\n[TOC]\n\nBody."
        let ranges = try await TOCContribution.findMarkers(in: text, document: Self.document(text))

        #expect(ranges.count == 1)
        let range = try #require(ranges.first)
        let nsRange = NSRange(location: range.lowerBound, length: range.count)
        #expect((text as NSString).substring(with: nsRange) == "[TOC]")
    }

    @Test func findMarkersIgnoresATextWithNoMarker() async throws {
        let text = "# Title\n\nJust a paragraph.\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersTrimsSurroundingWhitespace() async throws {
        let text = "  [TOC]  \n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).count == 1)
    }

    @Test func findMarkersHandlesACRLFTerminatedMarkerLine() async throws {
        let text = "Intro\r\n[TOC]\r\nMore\r\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).count == 1)
    }

    @Test func findMarkersRequiresTheWholeLineNotAnEmbeddedOccurrence() async throws {
        let text = "See [TOC] below for a table.\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersLocatesEveryOccurrence() async throws {
        let text = "[TOC]\n\nSection\n\n[TOC]\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).count == 2)
    }

    @Test func findMarkersAcceptsAMarkerInsideAMultiLineTopLevelParagraph() async throws {
        let text = "before\n[TOC]\nafter\n"
        let ranges = try await TOCContribution.findMarkers(in: text, document: Self.document(text))
        #expect(ranges.count == 1)
    }

    @Test func findMarkersRejectsFencedCodeBackticks() async throws {
        let text = "```\n[TOC]\n```\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersRejectsFencedCodeTildes() async throws {
        let text = "~~~\n[TOC]\n~~~\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersRejectsIndentedCode() async throws {
        let text = "Para.\n\n    [TOC]\n\nMore.\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersRejectsAnUnorderedListItem() async throws {
        let text = "- [TOC]\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersRejectsAnOrderedListItem() async throws {
        let text = "1. [TOC]\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersRejectsALazyListContinuation() async throws {
        let text = "- Item\n[TOC]\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersRejectsABlockQuote() async throws {
        let text = "> [TOC]\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersRejectsALazyBlockQuoteContinuation() async throws {
        let text = "> Quoted\n[TOC]\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersRejectsASetextHeading() async throws {
        let text = "[TOC]\n===\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersRejectsFrontMatter() async throws {
        let text = "---\n[TOC]\n---\n\nBody.\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersRejectsAnHTMLBlock() async throws {
        let text = "<div>\n[TOC]\n</div>\n"
        #expect(try await TOCContribution.findMarkers(in: text, document: Self.document(text)).isEmpty)
    }

    @Test func findMarkersHandlesCRLFAcceptedRangesExactly() async throws {
        let text = "Intro\r\n[TOC]\r\nMore\r\n"
        let document = try await Self.document(text)
        let ranges = TOCContribution.findMarkers(in: text, document: document)
        let range = try #require(ranges.first)
        let nsRange = NSRange(location: range.lowerBound, length: range.count)
        // The range stops before the whole CRLF terminator.
        #expect((text as NSString).substring(with: nsRange) == "[TOC]")
    }

    // MARK: - markdownList

    @Test func markdownListWithNoHeadingsIsANonEmptyPlaceholder() {
        let list = TOCContribution.markdownList(for: [])
        #expect(list == "*(No headings found\\.)*")
    }

    @Test func markdownListIsFlatForHeadingsOfTheSameLevel() {
        let headings = [
            HeadingItem(level: 1, title: "One", lineRange: 1 ... 1),
            HeadingItem(level: 1, title: "Two", lineRange: 2 ... 2),
        ]

        #expect(TOCContribution.markdownList(for: headings) == "- One\n- Two")
    }

    @Test func markdownListNestsDeeperLevelsUnderTheirParent() {
        let headings = [
            HeadingItem(level: 1, title: "Intro", lineRange: 1 ... 1),
            HeadingItem(level: 2, title: "Background", lineRange: 2 ... 2),
            HeadingItem(level: 3, title: "Detail", lineRange: 3 ... 3),
            HeadingItem(level: 2, title: "Scope", lineRange: 4 ... 4),
            HeadingItem(level: 1, title: "Conclusion", lineRange: 5 ... 5),
        ]

        let expected = """
        - Intro
          - Background
            - Detail
          - Scope
        - Conclusion
        """
        #expect(TOCContribution.markdownList(for: headings) == expected)
    }

    /// A level that skips ahead of its predecessor (H1 -> H3, no H2) nests
    /// one level under the nearest shallower heading rather than leaving a
    /// phantom empty level (epic-14-implementation.md §6.2).
    @Test func markdownListCollapsesSkippedLevels() {
        let headings = [
            HeadingItem(level: 1, title: "A", lineRange: 1 ... 1),
            HeadingItem(level: 3, title: "B", lineRange: 2 ... 2),
        ]

        #expect(TOCContribution.markdownList(for: headings) == "- A\n  - B")
    }

    @Test func markdownListEscapesCommonMarkPunctuationInTitles() {
        let headings = [HeadingItem(level: 1, title: "Use [brackets] and *stars*", lineRange: 1 ... 1)]

        #expect(TOCContribution.markdownList(for: headings) == "- Use \\[brackets\\] and \\*stars\\*")
    }

    @Test func linkedListEncodesAllocatedFragmentsOnceAndPreservesNesting() async throws {
        let text = "# Café\n## 100% ready\n# Café\n"
        let document = try await Self.document(text)
        let index = try HeadingAnchorIndex(
            document: document, sourceText: text, documentID: "toc-fixture",
            recoveryEpoch: UUID(), sourceGeneration: 1, reservedIDs: []
        )
        #expect(index.headings.map(\.fragment) == ["café", "100-ready", "café-1"])
        #expect(TOCContribution.linkedMarkdownList(for: index) ==
            "- [Café](#caf%C3%A9)\n  - [100% ready](#100-ready)\n- [Café](#caf%C3%A9-1)")
    }

    // MARK: - run (end-to-end, real parse)

    @Test func runProducesAPlacementForEachMarkerFromRealHeadings() async throws {
        let text = """
        # Title

        [TOC]

        ## Section One

        ## Section Two
        """
        let document = try await ParseEngine().parse(text, revision: 0)

        let results = try await TOCContribution().run(document: document, sourceText: text, sourceGeneration: 7)

        #expect(results.count == 1)
        let content = try #require(results.first?.content)
        #expect(content.placement == .block)
        guard case let .markdown(list) = content.representation else {
            Issue.record("expected a markdown representation")
            return
        }
        #expect(list.contains("Title"))
        #expect(list.contains("Section One"))
        #expect(list.contains("Section Two"))
        #expect(results.first?.sourceGeneration == 7)
    }

    @Test func runContributesNothingWhenThereIsNoMarker() async throws {
        let text = "# Title\n\nNo marker here.\n"
        let document = try await ParseEngine().parse(text, revision: 0)

        let results = try await TOCContribution().run(document: document, sourceText: text, sourceGeneration: 0)

        #expect(results.isEmpty)
    }

    /// Each marker scanned every top-level block (20k markers took ~36 s).
    @Test func manyMarkersAreFoundInLinearTime() async throws {
        let text = String(repeating: "[TOC]\n\n", count: 20000)
        let document = try await Self.document(text)
        let start = ContinuousClock.now

        let ranges = TOCContribution.findMarkers(in: text, document: document)

        #expect(ranges.count == 20000)
        #expect(ContinuousClock.now - start < .seconds(10))
    }
}
