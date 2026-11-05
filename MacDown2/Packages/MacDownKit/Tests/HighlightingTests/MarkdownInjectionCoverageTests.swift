import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterMarkdownInlineResources
import TreeSitterMarkdownResources

@Suite("Moved Markdown injection capture coverage", .serialized)
struct MarkdownInjectionCoverageTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func newlineReplacementKeepsTheRemainingInlineParagraph(ending: String) throws {
        let root = try LanguageConfiguration(tree_sitter_markdown(), name: "Markdown",
                                             queriesURL: #require(TreeSitterMarkdownResources.queriesURL))
        // Retain the default reuse policy to test query coverage independently.
        let inline = try LanguageConfiguration(tree_sitter_markdown_inline(), name: "MarkdownInline",
                                               queriesURL: #require(TreeSitterMarkdownInlineResources.queriesURL))
        let configuration = LanguageLayer.Configuration(languageProvider: { $0 == "markdown_inline" ? inline : nil })
        let before = "*café **bold** `code`*" + ending + ending + "Later **strong**." + ending
        let after = (before as NSString).replacingCharacters(in: NSRange(location: 1, length: 1), with: ending)
        let edited = try LanguageLayer(languageConfig: root, configuration: configuration)
        _ = edited.replaceContent(with: before)
        let prefix = Array(after.utf16.prefix(1 + ending.utf16.count))
        let row = prefix.filter { $0 == 10 }.count
        let lineStart = prefix.lastIndex(of: 10).map { $0 + 1 } ?? 0
        _ = edited.didChangeContent(.init(string: after), using: InputEdit(
            startByte: 2, oldEndByte: 4, newEndByte: UInt32((1 + ending.utf16.count) * 2),
            startPoint: Point(row: 0, column: 2), oldEndPoint: Point(row: 0, column: 4),
            newEndPoint: Point(row: row, column: (prefix.count - lineStart) * 2)
        ), resolveSublayers: false)
        // Resolve only the changed prefix. The replacement inline capture
        // starts exactly beyond this window, inside the old capture's extent.
        _ = try edited.resolveSublayers(
            with: .init(string: after),
            in: IndexSet(integersIn: 0 ..< (1 + ending.utf16.count))
        )
        let fresh = try LanguageLayer(languageConfig: root, configuration: configuration)
        _ = fresh.replaceContent(with: after)
        let actualTree = try #require(edited.snapshot()?.sublayerSnapshots.first?.rootSnapshot.tree)
        let expectedTree = try #require(fresh.snapshot()?.sublayerSnapshots.first?.rootSnapshot.tree)
        #expect(edited.snapshot()?.rootSnapshot.tree.rootNode?.sExpressionString == fresh.snapshot()?.rootSnapshot.tree
            .rootNode?.sExpressionString)
        #expect(actualTree.includedRanges == expectedTree.includedRanges)
        let range = IndexSet(integersIn: 0 ..< after.utf16.count)
        let actual = try edited.executeQuery(.highlights, in: range)
            .resolve(with: .init(textProvider: after.predicateTextProvider)).highlights()
        let expected = try fresh.executeQuery(.highlights, in: range)
            .resolve(with: .init(textProvider: after.predicateTextProvider)).highlights()
        #expect(actual == expected)
    }
}
