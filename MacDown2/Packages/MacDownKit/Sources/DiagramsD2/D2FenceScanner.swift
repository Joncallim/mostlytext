import Foundation
import MarkdownEngine

/// Finds every ```d2``` fenced code block in a document, at any nesting
/// depth, mirroring `MermaidFenceScanner`'s exact approach
/// (epic-21-implementation.md §3.2, §3.4).
public enum D2FenceScanner {
    public static func scan(_ document: MarkdownDocument, sourceText: String) -> [D2Fence] {
        document.blocks.flatMap { scan($0, sourceMap: document.sourceMap, sourceText: sourceText) }
    }

    private static func scan(
        _ block: MarkdownBlock,
        sourceMap: SourceMap,
        sourceText: String
    ) -> [D2Fence] {
        switch block.kind {
        case let .codeBlock(language):
            guard let language, language.caseInsensitiveCompare("d2") == .orderedSame else {
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

    /// Uses parser-decoded content while preserving original source coordinates.
    /// Older manually constructed nodes retain the legacy delimiter fallback.
    private static func fence(
        for block: MarkdownBlock,
        sourceMap: SourceMap,
        sourceText: String
    ) -> D2Fence? {
        let nsRange = sourceMap.utf16Range(ofLines: block.lineRange)
        guard let range = Range(nsRange, in: sourceText) else { return nil }
        let inner = block.codeBlockContent ?? D2FenceContent.stripDelimiters(from: String(sourceText[range]))
        return D2Fence(source: inner, sourceRange: nsRange.location ..< (nsRange.location + nsRange.length))
    }
}
