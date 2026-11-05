import Foundation

/// One `$...$` or `$$...$$` span found in a document's raw source text.
public struct MathSpan: Sendable, Equatable {
    public enum Style: Sendable, Equatable {
        case inline
        case display
    }

    /// UTF-16 offsets into the ORIGINAL source, covering the full span
    /// INCLUDING its delimiters — matching `ContributionContent.sourceRange`'s
    /// existing convention (epic-14-implementation.md §6.1) that a
    /// contribution's range is what it replaces, not merely what it reads.
    public let range: Range<Int>

    public let style: Style

    /// The LaTeX content WITHOUT the surrounding `$`/`$$` delimiters.
    public let latex: String

    public init(range: Range<Int>, style: Style, latex: String) {
        self.range = range
        self.style = style
        self.latex = latex
    }
}
