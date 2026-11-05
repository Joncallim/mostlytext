import Foundation
import MarkdownEngine

/// Finds every ```dot``` or ```graphviz``` fenced code block in a
/// document, at any nesting depth, mirroring `MermaidFenceScanner`'s
/// approach. Both aliases are genuinely, widely used elsewhere
/// (epic-21-implementation.md §3.4) and are mapped to the same renderer.
public enum GraphvizFenceScanner {
    private static let acceptedLanguages: Set<String> = ["dot", "graphviz"]

    public static func scan(_ document: MarkdownDocument, sourceText: String) -> [GraphvizFence] {
        document.blocks.flatMap { scan($0, sourceMap: document.sourceMap, sourceText: sourceText) }
    }

    private static func scan(
        _ block: MarkdownBlock,
        sourceMap: SourceMap,
        sourceText: String
    ) -> [GraphvizFence] {
        switch block.kind {
        case let .codeBlock(language):
            guard let language, acceptedLanguages.contains(language.lowercased()) else {
                return []
            }
            guard let fence = fence(for: block, sourceMap: sourceMap, sourceText: sourceText) else {
                return []
            }
            return [fence]
        default:
            return block.children.flatMap { scan($0, sourceMap: sourceMap, sourceText: sourceText) }
        }
    }

    private static func fence(
        for block: MarkdownBlock,
        sourceMap: SourceMap,
        sourceText: String
    ) -> GraphvizFence? {
        let nsRange = sourceMap.utf16Range(ofLines: block.lineRange)
        guard let range = Range(nsRange, in: sourceText) else { return nil }
        let inner = block.codeBlockContent ?? GraphvizFenceContent.stripDelimiters(from: String(sourceText[range]))
        return GraphvizFence(source: inner, sourceRange: nsRange.location ..< (nsRange.location + nsRange.length))
    }
}
