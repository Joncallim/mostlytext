import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterMarkdownInlineResources
import TreeSitterMarkdownResources

@Suite("Shared subtree Markdown comparison", .serialized)
struct SharedSubtreeComparisonTests {
    @Test func denseInlineEditsKeepFreshCapturesAndPreviouslyRetainedSnapshots() throws {
        for ending in ["\n", "\r\n", "\r"] {
            let source = ("# Shared café 雪 😀\n\n" + HighlightBudgetFixture.inlineDense.markdown(utf8Bytes: 64 * 1024))
                .replacingOccurrences(of: "\n", with: ending)
            let edited = try layer(source)
            let retained = try #require(edited.snapshot())
            let originalTree = try #require(retained.rootSnapshot.tree.rootNode?.sExpressionString)
            let originalHighlights = try retained.highlights(
                in: NSRange(location: 0, length: source.utf16.count), provider: source.predicateTextProvider
            )
            try #require(!originalHighlights.isEmpty)
            var text = source
            let edits = [
                ("**c**", "_changed_"), ("`code`", "`é 😀`"),
                ("https://example.com/", "https://example.invalid/"),
            ]
            for (needle, replacement) in edits {
                let range = (text as NSString).range(of: needle, options: .backwards)
                try #require(range.location != NSNotFound)
                let start = point(range.location, in: text)
                let oldEnd = point(range.upperBound, in: text)
                text = (text as NSString).replacingCharacters(in: range, with: replacement)
                let newEnd = range.location + replacement.utf16.count
                _ = edited.didChangeContent(.init(string: text), using: InputEdit(
                    startByte: range.location * 2, oldEndByte: range.upperBound * 2, newEndByte: newEnd * 2,
                    startPoint: start, oldEndPoint: oldEnd, newEndPoint: point(newEnd, in: text)
                ), resolveSublayers: true)
                _ = try edited.resolveSublayers(
                    with: .init(string: text),
                    in: IndexSet(integersIn: 0 ..< text.utf16.count)
                )
                try expectEquivalent(edited, to: layer(text), source: text)
                #expect(retained.rootSnapshot.tree.rootNode?.sExpressionString == originalTree)
                #expect(try retained.highlights(
                    in: NSRange(location: 0, length: source.utf16.count), provider: source.predicateTextProvider
                ) == originalHighlights)
            }
        }
    }

    private func layer(_ source: String) throws -> LanguageLayer {
        let blockURL = try #require(TreeSitterMarkdownResources.queriesURL)
        let inlineURL = try #require(TreeSitterMarkdownInlineResources.queriesURL)
        let block = try LanguageConfiguration(tree_sitter_markdown(), name: "Markdown", queriesURL: blockURL)
        var inline = try LanguageConfiguration(
            tree_sitter_markdown_inline(),
            name: "MarkdownInline",
            queriesURL: inlineURL
        )
        inline.reusesPreviousTree = false
        let layer = try LanguageLayer(languageConfig: block, configuration: .init(languageProvider: { [inline] in
            $0 == "markdown_inline" ? inline : nil
        }))
        _ = layer.replaceContent(with: source, transformer: { point($0, in: source) })
        return layer
    }

    private func point(_ offset: Int, in source: String) -> Point {
        let prefix = Array(source.utf16.prefix(offset))
        let start = prefix.lastIndex(of: 10).map { $0 + 1 } ?? 0
        return Point(row: prefix.filter { $0 == 10 }.count, column: (offset - start) * 2)
    }

    private func expectEquivalent(_ actual: LanguageLayer, to fresh: LanguageLayer, source: String) throws {
        let observed = try #require(actual.snapshot())
        let expected = try #require(fresh.snapshot())
        #expect(observed.rootSnapshot.tree.rootNode?.sExpressionString == expected.rootSnapshot.tree.rootNode?
            .sExpressionString)
        let actualInline = try #require(observed.sublayerSnapshots
            .first { $0.rootSnapshot.data.name == "MarkdownInline" })
        let freshInline = try #require(expected.sublayerSnapshots
            .first { $0.rootSnapshot.data.name == "MarkdownInline" })
        #expect(actualInline.rootSnapshot.tree.includedRanges == freshInline.rootSnapshot.tree.includedRanges)
        #expect(actualInline.rootSnapshot.tree.rootNode?.sExpressionString == freshInline.rootSnapshot.tree.rootNode?
            .sExpressionString)
        let range = NSRange(location: 0, length: source.utf16.count)
        let captures = try observed.highlights(in: range, provider: source.predicateTextProvider)
        try #require(!captures.isEmpty)
        #expect(try captures == (expected.highlights(in: range, provider: source.predicateTextProvider)))
    }
}
