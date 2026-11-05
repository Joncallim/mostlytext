import Foundation

/// Block kinds. `custom` is the totality escape hatch (ground rule 5).
public enum BlockKind: Sendable, Equatable {
    case heading(level: Int)
    case paragraph
    case codeBlock(language: String?)
    case blockQuote
    case orderedList(startIndex: Int)
    case unorderedList
    case listItem(taskState: TaskState?)
    case table(columnCount: Int)
    case thematicBreak
    case htmlBlock
    /// Reserved for future use. swift-markdown 0.8.0 does not expose a footnote
    /// parsing option, so this case is never produced by the current parser.
    case footnoteDefinition(label: String)
    case custom(String)

    public enum TaskState: Sendable, Equatable {
        case checked
        case unchecked
    }
}

/// One block node. A value tree — children are copies, no reference semantics.
public struct MarkdownBlock: Sendable, Equatable {
    public let kind: BlockKind

    /// 1-based lines of the ORIGINAL source (D4). Always non-empty, always
    /// within 1...sourceMap.lineCount.
    public let lineRange: ClosedRange<Int>

    public let children: [MarkdownBlock]

    /// Parser-decoded code text with Markdown container prefixes/delimiters removed.
    /// One parser-added terminal LF is omitted; genuine blank lines are retained.
    /// Nil for other nodes and older manually constructed models. Original source
    /// coordinates remain in `lineRange`; this value is only derived render input.
    public let codeBlockContent: String?

    public init(
        kind: BlockKind,
        lineRange: ClosedRange<Int>,
        children: [MarkdownBlock] = [],
        codeContent: String? = nil
    ) {
        self.kind = kind
        self.lineRange = lineRange
        self.children = children
        codeBlockContent = codeContent.map { $0.hasSuffix("\n") ? String($0.dropLast()) : $0 }
    }
}

/// A heading, flattened for E08. `title` is the plain-text inline content
/// (swift-markdown `plainText`), markup stripped.
public struct HeadingItem: Sendable, Equatable {
    public let level: Int
    public let title: String
    public let lineRange: ClosedRange<Int>

    public init(level: Int, title: String, lineRange: ClosedRange<Int>) {
        self.level = level
        self.title = title
        self.lineRange = lineRange
    }
}
