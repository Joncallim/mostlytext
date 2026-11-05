import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterMarkdownResources
import TreeSitterMarkdownInlineResources

@Suite("Component-only edit cost probe", .serialized)
struct ComponentEditCostProbe {
    @Test func eligibleLengths() throws {
        let root = try LanguageConfiguration(tree_sitter_markdown(), name: "Markdown", queriesURL: #require(TreeSitterMarkdownResources.queriesURL))
        var inline = try LanguageConfiguration(tree_sitter_markdown_inline(), name: "MarkdownInline", queriesURL: #require(TreeSitterMarkdownInlineResources.queriesURL))
        inline.reusesPreviousTree = false
        let configuration = LanguageLayer.Configuration(languageProvider: { $0 == "markdown_inline" ? inline : nil })
        for length in [1_000, 4_000, 8_000] {
            // One paragraph exercises the entire combined inline layer.
            var text = String(repeating: "*café **bold** `code`* ", count: length / 22 + 2)
            text = String(text.prefix(length))
            let layer = try LanguageLayer(languageConfig: root, configuration: configuration)
            _ = layer.replaceContent(with: text)
            var samples: [Double] = []
            for iteration in 0..<100 {
                let location = text.utf16.count / 2
                let range = NSRange(location: location, length: 1)
                let replacement = iteration % 2 == 0 ? "a" : "*"
                text = (text as NSString).replacingCharacters(in: range, with: replacement)
                let edit = InputEdit(startByte: UInt32(location * 2), oldEndByte: UInt32((location + 1) * 2), newEndByte: UInt32((location + 1) * 2), startPoint: Point(row: 0, column: location * 2), oldEndPoint: Point(row: 0, column: (location + 1) * 2), newEndPoint: Point(row: 0, column: (location + 1) * 2))
                let start = ContinuousClock.now
                _ = layer.didChangeContent(.init(string: text), using: edit, resolveSublayers: true)
                _ = try layer.executeQuery(.highlights, in: IndexSet(integersIn: 0..<text.utf16.count)).resolve(with: .init(textProvider: text.predicateTextProvider)).highlights()
                let duration = start.duration(to: .now).components
                samples.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
            }
            samples.sort()
            print("COMPONENT_EDIT_COST utf16=\(text.utf16.count) count=100 p50_ms=\(samples[50]) p95_ms=\(samples[95]) max_ms=\(samples.last!)")
        }
    }
}
