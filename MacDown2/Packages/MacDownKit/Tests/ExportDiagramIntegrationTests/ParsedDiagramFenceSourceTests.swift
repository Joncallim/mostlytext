import Diagrams
import DiagramsD2
import DiagramsGraphviz
import Foundation
import MarkdownEngine
import Testing

@Suite("Parsed diagram fence source")
struct ParsedDiagramFenceSourceTests {
    private static let languages = ["mermaid", "d2", "dot", "graphviz"]

    @Test(arguments: languages)
    func quotedContentHasNoMarkdownPrefixes(language: String) async throws {
        try await check(
            "> ```\(language)\n> a -> b\n> ```",
            language: language, expected: "a -> b"
        )
    }

    @Test(arguments: languages)
    func nestedQuotesAndLongTildeDelimiters(language: String) async throws {
        try await check(
            "> > ~~~~\(language)\n> > a -> b\n> > ~~~~~",
            language: language, expected: "a -> b"
        )
    }

    @Test(arguments: languages)
    func fenceOnTheListMarkerLine(language: String) async throws {
        try await check(
            "- ```\(language)\n  a -> b\n  ```",
            language: language, expected: "a -> b", suffix: "\n- sibling"
        )
    }

    @Test(arguments: languages)
    func quoteInsideAList(language: String) async throws {
        try await check(
            "- > ```\(language)\n  > a -> b\n  > ```",
            language: language, expected: "a -> b", suffix: "\n- sibling"
        )
    }

    @Test(arguments: languages)
    func unterminatedQuoteStopsAtItsContainer(language: String) async throws {
        try await check(
            "> ```\(language)\n> a -> b",
            language: language, expected: "a -> b", suffix: "\n\noutside"
        )
    }

    @Test(arguments: languages)
    func overindentedBackticksRemainAuthoredContent(language: String) async throws {
        try await check(
            "```\(language)\na -> b\n    ```",
            language: language, expected: "a -> b\n    ```"
        )
    }

    @Test(arguments: languages)
    func genuineOperatorsIndentationAndBlankLinesSurvive(language: String) async throws {
        try await check(
            "> ```\(language)\n>   a > b\n>\n>     indented\n>\n> ```",
            language: language, expected: "  a > b\n\n    indented\n"
        )
    }

    @Test(arguments: languages)
    func emptyAndBlankBodiesRemainDistinct(language: String) async throws {
        try await check("```\(language)\n```", language: language, expected: "")
        try await check("```\(language)\n\n\n```", language: language, expected: "\n")
    }

    @Test(arguments: languages)
    func originalUnicodeAndMixedEndingRangesArePreserved(language: String) async throws {
        for ending in ["\n", "\r\n", "\r"] {
            let prefix = "---\ntitle: café\n---\n🙂 heading\n\n"
            let fence = "> ```\(language)\(ending)> a -> b\(ending)> ```"
            try await check(fence, language: language, expected: "a -> b", prefix: prefix)
        }
    }

    @Test func manualModelsRetainTheLegacyFallback() async throws {
        for language in Self.languages {
            try await check("```\(language)\na -> b\n```", language: language, expected: "a -> b", manual: true)
        }
    }

    private func check(
        _ fence: String, language: String, expected: String, prefix: String = "", suffix: String = "",
        manual: Bool = false
    ) async throws {
        let source = prefix + fence + suffix
        let document: MarkdownDocument = if manual {
            MarkdownDocument(
                body: source, bodyLineOffset: 0,
                blocks: [MarkdownBlock(kind: .codeBlock(language: language), lineRange: 1 ... 3)],
                headings: [], frontMatter: nil, sourceMap: SourceMap(text: source), revision: 7, options: .default
            )
        } else {
            try await ParseEngine().parse(source, revision: 7)
        }
        let values: [(source: String, range: Range<Int>)] = switch language {
        case "mermaid":
            MermaidFenceScanner.scan(document, sourceText: source).map { ($0.source, $0.sourceRange) }
        case "d2":
            D2FenceScanner.scan(document, sourceText: source).map { ($0.source, $0.sourceRange) }
        default:
            GraphvizFenceScanner.scan(document, sourceText: source).map { ($0.source, $0.sourceRange) }
        }
        let value = try #require(values.count == 1 ? values.first : nil)
        #expect(value.source == expected)
        #expect(value.range == prefix.utf16.count ..< (prefix.utf16.count + fence.utf16.count))
        let originalRange = NSRange(location: value.range.lowerBound, length: value.range.count)
        #expect((source as NSString).substring(with: originalRange) == fence)
        #expect(document.bodyLineOffset == (prefix.hasPrefix("---") ? 3 : 0))
        #expect(document.revision == 7)
    }
}
