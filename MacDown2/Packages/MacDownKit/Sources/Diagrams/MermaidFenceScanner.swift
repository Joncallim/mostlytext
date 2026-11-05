import Foundation
import MarkdownEngine

/// Finds every ```mermaid``` fenced code block in a document, at any
/// nesting depth (epic-20-implementation.md §6, §16). Unlike `MathSpanScanner`
/// (which scans raw text for a delimiter pattern that could coincidentally
/// appear anywhere, including inside unrelated code), this scanner walks the
/// already-parsed block tree looking for a specific, unambiguous block kind
/// — `.codeBlock(language:)` tagged "mermaid" — so it never needs an
/// exclusion list the way `MathContribution.excludedRanges(in:)` does.
///
/// Recurses into `block.children` rather than only `document.blocks`
/// (top-level siblings), matching the lesson learned and fixed for `Math`
/// (epic-19-implementation.md §21): a fenced code block nested inside a list
/// item or block quote is a CHILD of that block in `MarkdownBlock`'s tree,
/// not a top-level sibling, and would be silently missed by a shallow scan.
public enum MermaidFenceScanner {
    public static func scan(_ document: MarkdownDocument, sourceText: String) -> [MermaidFence] {
        document.blocks.flatMap { scan($0, sourceMap: document.sourceMap, sourceText: sourceText) }
    }

    private static func scan(
        _ block: MarkdownBlock,
        sourceMap: SourceMap,
        sourceText: String
    ) -> [MermaidFence] {
        switch block.kind {
        case let .codeBlock(language):
            guard let language, language.caseInsensitiveCompare("mermaid") == .orderedSame else {
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
    ) -> MermaidFence? {
        let nsRange = sourceMap.utf16Range(ofLines: block.lineRange)
        guard let range = Range(nsRange, in: sourceText) else { return nil }
        let inner = block.codeBlockContent ?? MermaidFenceContent.stripDelimiters(from: String(sourceText[range]))
        return MermaidFence(source: inner, sourceRange: nsRange.location ..< (nsRange.location + nsRange.length))
    }
}
