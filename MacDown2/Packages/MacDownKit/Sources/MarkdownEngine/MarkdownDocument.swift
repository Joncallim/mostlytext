import Foundation

/// The complete parse result. Immutable snapshot; a new value per parse.
public struct MarkdownDocument: Sendable, Equatable {
    /// The source WITHOUT the front-matter lines — what E07 hands to the renderer.
    public let body: String

    /// Number of original-source lines occupied by front matter (0 if none).
    public let bodyLineOffset: Int

    /// Block tree in document order (top-level blocks; children nested).
    public let blocks: [MarkdownBlock]

    /// All headings in document order (flattened from `blocks`).
    public let headings: [HeadingItem]

    public let frontMatter: FrontMatter?

    /// Line table of the ORIGINAL source (front matter included).
    public let sourceMap: SourceMap

    /// Digest of the complete immutable input consumed by ParseEngine, including
    /// front-matter delimiters and whitespace. Nil on unbound manual models.
    public let sourceSHA256: String?

    /// Exact parser-owned source projection. Nil for unbound/manual or unsupported coordinates.
    public let sourceFacts: MarkdownSourceFacts?

    /// The revision passed to the parse that produced this document.
    public let revision: Int

    /// The options the parse ran with.
    public let options: MarkdownParseOptions

    public init(
        body: String,
        bodyLineOffset: Int,
        blocks: [MarkdownBlock],
        headings: [HeadingItem],
        frontMatter: FrontMatter?,
        sourceMap: SourceMap,
        revision: Int,
        options: MarkdownParseOptions,
        sourceSHA256: String? = nil,
        sourceFacts: MarkdownSourceFacts? = nil
    ) {
        self.body = body
        self.bodyLineOffset = bodyLineOffset
        self.blocks = blocks
        self.headings = headings
        self.frontMatter = frontMatter
        self.sourceMap = sourceMap
        self.sourceSHA256 = sourceSHA256
        self.sourceFacts = sourceFacts
        self.revision = revision
        self.options = options
    }

    /// Block whose lineRange contains `line`; nil when the line is blank
    /// between blocks or inside front matter. For list items, the item itself
    /// is returned rather than its nested paragraph child so callers receive
    /// the logical container.
    public func block(atLine line: Int) -> MarkdownBlock? {
        block(containing: line, in: blocks)
    }

    private func block(containing line: Int, in candidates: [MarkdownBlock]) -> MarkdownBlock? {
        for block in candidates {
            guard block.lineRange.contains(line) else {
                continue
            }
            // List items are containers, but callers expect the item itself as
            // the deepest returned block (not its paragraph child).
            if case .listItem = block.kind {
                return block
            }
            if let child = self.block(containing: line, in: block.children) {
                return child
            }
            return block
        }
        return nil
    }
}
