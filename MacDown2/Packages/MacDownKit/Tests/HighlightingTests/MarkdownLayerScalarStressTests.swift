import Foundation
#if canImport(Highlighting)
    import Highlighting
#endif
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterMarkdownInlineResources
import TreeSitterMarkdownResources

@MainActor
@Suite("Actual Markdown layer scalar-edit parity", .serialized)
struct MarkdownLayerScalarStressTests {
    @Test(.timeLimit(.minutes(1)))
    func editedRootAndInlineLayersMatchFresh() throws {
        let (root, inline) = try configurations()
        let configuration = LanguageLayer.Configuration(languageProvider: { $0 == "markdown_inline" ? inline : nil })
        var corpus = ScalarEditCorpus()
        let edited = try LanguageLayer(languageConfig: root, configuration: configuration)
        _ = edited.replaceContent(with: corpus.document)
        for iteration in 0 ..< 2000 {
            let edit = corpus.nextEdit()
            let text = corpus.document
            _ = edited.didChangeContent(.init(string: text), using: edit, resolveSublayers: true)
            let fresh = try LanguageLayer(languageConfig: root, configuration: configuration)
            _ = fresh.replaceContent(with: text)
            let range = IndexSet(integersIn: 0 ..< text.utf16.count)
            let actual = try edited.executeQuery(.highlights, in: range)
                .resolve(with: .init(textProvider: text.predicateTextProvider)).highlights()
            let expected = try fresh.executeQuery(.highlights, in: range)
                .resolve(with: .init(textProvider: text.predicateTextProvider)).highlights()
            try #require(actual == expected, "actual root/injection query parity at scalar edit \(iteration)")
        }
    }

    private func configurations() throws -> (LanguageConfiguration, LanguageConfiguration) {
        #if canImport(Highlighting)
            let registry = GrammarRegistry()
            return try (
                #require(registry.configuration(for: "markdown")),
                #require(registry.configuration(for: "markdown_inline"))
            )
        #else
            let rootURL = try #require(TreeSitterMarkdownResources.queriesURL)
            let inlineURL = try #require(TreeSitterMarkdownInlineResources.queriesURL)
            let root = try LanguageConfiguration(tree_sitter_markdown(), name: "Markdown", queriesURL: rootURL)
            var inline = try LanguageConfiguration(
                tree_sitter_markdown_inline(),
                name: "MarkdownInline",
                queriesURL: inlineURL
            )
            inline.reusesPreviousTree = false
            return (root, inline)
        #endif
    }
}

private struct ScalarEditCorpus {
    private var bodies = Array(repeating: Array("*café 漢😀 **bold** and `code`*".unicodeScalars), count: 12)
    private let additions = Array("a*`[]\n\ré漢😀".unicodeScalars)
    private var seed: UInt32 = 0x2468_ACE0

    var document: String {
        bodies.map(string).joined(separator: "\n\n")
    }

    mutating func nextEdit() -> InputEdit {
        let text = document
        let segment = Int(random() % 12)
        let offset = Int(random() % UInt32(bodies[segment].count + 1))
        let operation = random() % 3
        var remove = offset < bodies[segment].count && operation != 0 ? 1 : 0
        var insertion: [Unicode.Scalar] = operation != 1 || bodies[segment]
            .isEmpty ? [additions[Int(random() % UInt32(additions.count))]] : []
        if bodies[segment].count + insertion.count - remove > 128 {
            insertion = []
            if offset < bodies[segment].count {
                remove = 1
            }
        }
        let prefix = bodies.prefix(segment).map(string).joined(separator: "\n\n")
        let location = prefix.utf16.count + (segment == 0 ? 0 : 2) + string(Array(bodies[segment].prefix(offset))).utf16
            .count
        let oldLength = string(Array(bodies[segment][offset ..< (offset + remove)])).utf16.count
        let newLength = string(insertion).utf16.count
        let oldStart = point(location, in: text), oldEnd = point(location + oldLength, in: text)
        bodies[segment].replaceSubrange(offset ..< (offset + remove), with: insertion)
        return InputEdit(startByte: UInt32(location * 2), oldEndByte: UInt32((location + oldLength) * 2),
                         newEndByte: UInt32((location + newLength) * 2), startPoint: oldStart,
                         oldEndPoint: oldEnd, newEndPoint: point(location + newLength, in: document))
    }

    private mutating func random() -> UInt32 {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return seed
    }

    private func string(_ body: [Unicode.Scalar]) -> String {
        String(String.UnicodeScalarView(body))
    }

    private func point(_ location: Int, in text: String) -> Point {
        let units = Array(text.utf16.prefix(location))
        let row = units.filter { $0 == 10 }.count
        let start = units.lastIndex(of: 10).map { $0 + 1 } ?? 0
        return Point(row: row, column: (location - start) * 2)
    }
}
