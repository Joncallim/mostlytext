import Foundation
import MathSyntax

public struct MathExpressionSourceSegment: Sendable, Equatable {
    public let renderedRange: Range<Int>
    public let sourceRange: Range<Int>
}

/// An occurrence, rather than an expression cache key. Original syntax and
/// renderer TeX have deliberately separate coordinates and values.
public struct MathEquation: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let syntax: MathSyntaxSpan
    public let rendererExpression: String
    public let expressionSegments: [MathExpressionSourceSegment]

    /// Converts a renderer boundary without splitting a surrogate or CRLF.
    /// At a removed-prefix boundary the following kept source character wins.
    public func sourceOffset(forRenderedUTF16Offset offset: Int) -> Int? {
        let units = Array(rendererExpression.utf16)
        guard offset >= 0, offset <= units.count, Self.boundary(offset, units: units) else { return nil }
        if offset == units.count {
            return syntax.bodyRange.upperBound
        }
        guard let segment = expressionSegments.first(where: { $0.renderedRange.contains(offset) }) else { return nil }
        return segment.sourceRange.lowerBound + offset - segment.renderedRange.lowerBound
    }

    private static func boundary(_ offset: Int, units: [UInt16]) -> Bool {
        guard offset > 0, offset < units.count else { return true }
        let previous = units[offset - 1], current = units[offset]
        if previous == 13, current == 10 {
            return false
        }
        return !(0xD800 ... 0xDBFF).contains(previous) || !(0xDC00 ... 0xDFFF).contains(current)
    }
}
