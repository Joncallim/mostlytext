import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterMarkdownInlineResources
import TreeSitterMarkdownResources

@Suite("Markdown included range reconciliation", .serialized)
struct MarkdownIncludedRangeReconciliationTests {
    enum EditShape: CaseIterable {
        case typing, replacement, deletion, combined, removeMarkup, removeAll, empty
    }

    struct Edit {
        let range: NSRange
        let replacement: String
    }

    @Test(arguments: EditShape.allCases, [false, true])
    func editedLayersMatchFreshSource(_ shape: EditShape, wholeDocument: Bool) throws {
        for ending in ["\n", "\r\n", "\r"] {
            let source = fixture(ending: ending)
            let edited = try layer(source)
            var text = source
            var invalidated = IndexSet()
            for edit in edits(shape, text: source) {
                invalidated = apply(edit, to: &text, layer: edited, invalidated: invalidated)
            }
            let coverage = wholeDocument ? IndexSet(integersIn: 0 ..< text.utf16.count) : invalidated
            _ = try edited.resolveSublayers(with: .init(string: text), in: coverage)
            try expectEquivalent(edited, to: layer(text), text: text)
        }
    }

    private func fixture(ending: String) -> String {
        let block = """
        # Heading with `code`

        Some *emphasis*, **strong** text and a [link](https://example.com).
        Unicode café é 👩🏽‍💻 with `inline` and **bold**.

        - list item with `inline`
        > a quote with **bold**

        ```
        fenced code line
        ```


        """.replacingOccurrences(of: "\n", with: ending)
        return String(repeating: block, count: 24)
    }

    private func edits(_ shape: EditShape, text: String) -> [Edit] {
        let source = text as NSString
        let middle = source.length / 2
        let range = NSRange(location: middle, length: 600)
        switch shape {
        case .typing:
            return [Edit(range: NSRange(location: middle, length: 0), replacement: "x")]
        case .replacement:
            return [Edit(range: range, replacement: source.substring(with: range) + "y")]
        case .deletion:
            return [Edit(range: NSRange(location: 900, length: 600), replacement: "")]
        case .combined:
            return [
                Edit(range: NSRange(location: middle, length: 0), replacement: "x"),
                Edit(range: NSRange(location: 300, length: 600), replacement: ""),
            ]
        case .removeMarkup:
            return [Edit(range: range, replacement: String(repeating: "plain text ", count: 30))]
        case .empty:
            return [Edit(range: NSRange(location: 0, length: source.length), replacement: "")]
        case .removeAll:
            return [Edit(range: NSRange(location: 0, length: source.length), replacement: "````\nplain\n````\n")]
        }
    }

    private func layer(_ text: String) throws -> LanguageLayer {
        let blockURL = try #require(TreeSitterMarkdownResources.queriesURL)
        let inlineURL = try #require(TreeSitterMarkdownInlineResources.queriesURL)
        let block = try LanguageConfiguration(tree_sitter_markdown(), name: "Markdown", queriesURL: blockURL)
        let inline = try LanguageConfiguration(
            tree_sitter_markdown_inline(), name: "MarkdownInline", queriesURL: inlineURL
        )
        let configuration = LanguageLayer.Configuration(languageProvider: { $0 == "markdown_inline" ? inline : nil })
        let result = try LanguageLayer(languageConfig: block, configuration: configuration)
        _ = result.replaceContent(with: text, transformer: { point($0, in: text) })
        return result
    }

    private func point(_ location: Int, in text: String) -> Point {
        let prefix = Array(text.utf16.prefix(location))
        let row = prefix.filter { $0 == 10 }.count
        let start = prefix.lastIndex(of: 10).map { $0 + 1 } ?? 0
        return Point(row: row, column: (location - start) * 2)
    }

    private func apply(_ edit: Edit, to text: inout String, layer: LanguageLayer, invalidated: IndexSet) -> IndexSet {
        let start = point(edit.range.location, in: text)
        let oldEnd = point(edit.range.upperBound, in: text)
        text = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        let newEnd = edit.range.location + edit.replacement.utf16.count
        let change = InputEdit(
            startByte: edit.range.location * 2,
            oldEndByte: edit.range.upperBound * 2,
            newEndByte: newEnd * 2,
            startPoint: start, oldEndPoint: oldEnd, newEndPoint: point(newEnd, in: text)
        )
        var shifted = invalidated
        shifted.shift(startingAt: edit.range.upperBound, by: edit.replacement.utf16.count - edit.range.length)
        shifted.formUnion(layer.didChangeContent(.init(string: text), using: change, resolveSublayers: false))
        return shifted
    }

    private func expectEquivalent(_ actual: LanguageLayer, to expected: LanguageLayer, text: String) throws {
        let actualRoot = try #require(actual.snapshot())
        let expectedRoot = try #require(expected.snapshot())
        #expect(actualRoot.rootSnapshot.tree.rootNode?.sExpressionString == expectedRoot.rootSnapshot.tree.rootNode?
            .sExpressionString)
        let actualInline = actualRoot.sublayerSnapshots.first { $0.rootSnapshot.data.name == "MarkdownInline" }
        let expectedInline = expectedRoot.sublayerSnapshots.first { $0.rootSnapshot.data.name == "MarkdownInline" }
        #expect(actualInline?.rootSnapshot.tree.includedRanges == expectedInline?.rootSnapshot.tree.includedRanges)
        #expect(actualInline?.rootSnapshot.tree.rootNode?.sExpressionString == expectedInline?.rootSnapshot.tree
            .rootNode?.sExpressionString)
        let range = NSRange(location: 0, length: text.utf16.count)
        let actualCaptures = try actual.highlights(in: range, provider: text.predicateTextProvider)
        let expectedCaptures = try expected.highlights(in: range, provider: text.predicateTextProvider)
        #expect(actualCaptures == expectedCaptures)
    }
}
