import Foundation
import MathSyntax
import Testing

enum MathSyntaxTestSupport {
    struct ExpectedToken {
        let full: String
        let expression: String
        let style: MathDelimiterStyle

        init(_ full: String, _ expression: String, _ style: MathDelimiterStyle) {
            self.full = full
            self.expression = expression
            self.style = style
        }
    }

    static func scan(_ source: String, regions: [Range<Int>]? = nil, exclusions: [Range<Int>] = [],
                     maximumSpanCount: Int = 1000, identity: MathSourceIdentity? = nil) throws -> MathScanResult {
        try MathTokenizer.scan(source, identity: identity ?? MathSourceIdentity(rawValue: UUID()),
                               regions: regions ?? [0 ..< source.utf16.count], exclusions: exclusions,
                               maximumSpanCount: maximumSpanCount)
    }

    static func expect(_ result: MathScanResult, source: String,
                       tokens: [ExpectedToken]) throws {
        try #require(result.spans.count == tokens.count)
        let original = source as NSString
        var cursor = 0
        for (span, expected) in zip(result.spans, tokens) {
            let range = original.range(
                of: expected.full, options: .literal,
                range: NSRange(location: cursor, length: original.length - cursor)
            )
            try #require(range.location != NSNotFound)
            let full = range.location ..< range.upperBound
            let width = expected.style == .inline ? 1 : 2
            #expect(span.fullRange == full)
            #expect(span.bodyRange == (full.lowerBound + width) ..< (full.upperBound - width))
            #expect(span.style == expected.style)
            #expect(Array(span.expression.utf16) == Array(expected.expression.utf16))
            #expect(Array(span.expression.utf16) == Array(Array(source.utf16)[span.bodyRange]))
            cursor = range.upperBound
        }
    }
}
