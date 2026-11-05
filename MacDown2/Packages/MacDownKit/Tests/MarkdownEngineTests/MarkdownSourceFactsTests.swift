import Foundation
@testable import MarkdownEngine
import Testing

struct MarkdownSourceFactsTests {
    private func slice(_ source: String, _ range: Range<Int>) -> String {
        String(decoding: Array(source.utf16)[range], as: UTF16.self)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func originalUnicodeAndFrontMatterCoordinates(ending: String) async throws {
        let source = ["---", "name: example", "---", "漢😀 before [$x$][]", "", "[$x$]: /target \"title\""]
            .joined(separator: ending)
        let document = try await ParseEngine().parse(source, revision: 7)
        let facts = try #require(document.sourceFacts)
        #expect(facts.sourceSHA256 == document.sourceSHA256)
        let link = try #require(facts.links.first)
        #expect(slice(source, link.fullRange) == "[$x$][]")
        #expect(try slice(source, #require(link.labelRange)) == "$x$")
        #expect(link.referenceKey == "$x$")
        #expect(link.destination == "/target")
        #expect(link.title == "title")
        #expect(facts.inlineRegions.map { slice(source, $0) } == ["漢😀 before [$x$][]"])
        #expect(document.revision == 7)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func nestedContainerPrefixesKeepExactNewlines(ending: String) async throws {
        let source = "> - before $$x % comment" + ending + ">   +y$$ after"
        let facts = try #require(try await ParseEngine().parse(source, revision: 1).sourceFacts)
        #expect(facts.inlineRegions.map { slice(source, $0) } == ["before $$x % comment" + ending + ">   +y$$ after"])
        #expect(facts.continuationPrefixes.map { slice(source, $0) } == [">   "])
    }

    @Test func literalCodeImagesAndHTMLHaveTheirOwnRanges() async throws {
        let source = "`$literal$` then $x$ and <span title='$attribute$'>$y$</span> ![image $alt$](/img)"
        let facts = try #require(try await ParseEngine().parse(source, revision: 1).sourceFacts)
        #expect(facts.literalRanges.map { slice(source, $0) } == [
            "`$literal$`", "<span title='$attribute$'>", "</span>", "![image $alt$](/img)",
        ])
        #expect(facts.links.isEmpty)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func codeBlocksAndReferenceDefinitionsAreNotRegions(ending: String) async throws {
        let source = [
            "> - ```tex", ">   $literal$", ">   ```", "", "    $indented$", "",
            "[key]: /$destination$", "", "$real$",
        ].joined(separator: ending)
        let facts = try #require(try await ParseEngine().parse(source, revision: 1).sourceFacts)
        #expect(facts.inlineRegions.map { slice(source, $0) } == ["$real$"])
    }

    @Test func everyTableCellIsAnIndependentRegion() async throws {
        let source = "| A | B |\n|---|---|\n| $x$ | $y$ |"
        let facts = try #require(try await ParseEngine().parse(source, revision: 1).sourceFacts)
        #expect(facts.inlineRegions.map { slice(source, $0) } == ["A", "B", "$x$", "$y$"])
    }

    @Test func preserveReferenceSpellingAndDoNotUseAutolinkHeuristic() async throws {
        let source = "[www.example.com](www.example.com) [**$x$**][] [a \\] $y$][key] [$z$] <https://example.com>\n\n" +
            "[**$x$**]: /first \"title\"\n[key]: /second\n[$z$]: /third"
        let facts = try #require(try await ParseEngine().parse(source, revision: 1).sourceFacts)
        #expect(facts.links.count == 5)
        #expect(facts.links.map(\.referenceKey) == [nil, "**$x$**", "key", "$z$", nil])
        #expect(facts.links.map(\.destination) == [
            "www.example.com",
            "/first",
            "/second",
            "/third",
            "https://example.com",
        ])
        #expect(facts.links.compactMap(\.labelRange).map { slice(source, $0) } == [
            "www.example.com", "**$x$**", "a \\] $y$", "$z$",
        ])
    }

    @Test func bracketsInsideCodeDoNotEndALinkLabel() async throws {
        let source = "[code `]` and $x$](/target)"
        let facts = try #require(try await ParseEngine().parse(source, revision: 1).sourceFacts)
        #expect(try slice(source, #require(facts.links.first?.labelRange)) == "code `]` and $x$")
    }

    @Test func tabsAreByteColumnsAndNotVisualTabStops() async throws {
        let source = ">\t$x$\n\n-\t$y$ and [$z$](/target)"
        let facts = try #require(try await ParseEngine().parse(source, revision: 1).sourceFacts)
        #expect(facts.inlineRegions.map { slice(source, $0) } == ["$x$", "$y$ and [$z$](/target)"])
        #expect(try slice(source, #require(facts.links.first?.labelRange)) == "$z$")
    }

    @Test func coordinatesRejectInteriorBytesAndTerminators() throws {
        let point = MarkdownSourcePoint.init
        let source = "漢😀\r\nX\rY\n"
        let valid: Set = [point(1, 1), point(1, 4), point(1, 8), point(2, 1), point(2, 2), point(3, 1), point(4, 1)]
        let offsets = try #require(MarkdownSourceCoordinates.resolve(valid, in: source))
        #expect(valid.sorted().compactMap { offsets[$0] } == [0, 1, 3, 5, 6, 7, 9])
        for invalid in [point(0, 1), point(1, 0), point(1, 2), point(1, 5), point(1, 9), point(2, 3), point(5, 1)] {
            #expect(MarkdownSourceCoordinates.resolve([invalid], in: source) == nil)
        }
    }

    @Test func emptyAndLiteralOnlySourcesProduceBoundEmptyFacts() async throws {
        for source in ["", "```\n$x$\n```", "<div>\n$x$\n</div>"] {
            let document = try await ParseEngine().parse(source, revision: 1)
            let facts = try #require(document.sourceFacts)
            #expect(facts.sourceSHA256 == document.sourceSHA256)
            #expect(facts.inlineRegions.isEmpty)
        }
    }

    @Test func brokenUpstreamParagraphTableCoordinatesFailClosed() async throws {
        let source = "before\n| A | B |\n|---|---|\n| $x$ | $y$ |"
        let document = try await ParseEngine().parse(source, revision: 1)
        #expect(document.sourceFacts == nil)
        #expect(!document.blocks.isEmpty)
    }

    @Test func veryDeepStructuresFailClosed() async throws {
        let source = String(repeating: "> ", count: 140) + "$x$"
        let document = try await ParseEngine().parse(source, revision: 1)
        #expect(document.sourceFacts == nil)
        #expect(!document.blocks.isEmpty)
    }
}
