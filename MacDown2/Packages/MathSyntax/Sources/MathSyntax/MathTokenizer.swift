import Foundation

public enum MathTokenizer {
    /// Tokenizes only caller-admitted structural regions, preserving original source.
    /// This synchronous operation belongs on the caller's bounded analysis worker.
    public static func scan(
        _ source: String,
        identity: MathSourceIdentity,
        regions: [Range<Int>],
        exclusions: [Range<Int>] = [],
        maximumSpanCount: Int
    ) throws -> MathScanResult {
        try Task.checkCancellation()
        guard maximumSpanCount >= 0 else { throw MathSyntaxError.invalidMaximumSpanCount }
        let units = Array(source.utf16)
        let segments = try MathSourceIntervals.segments(units: units, regions: regions, exclusions: exclusions)
        var spans: [MathSyntaxSpan] = []
        if maximumSpanCount == 0 {
            try Task.checkCancellation()
            return MathScanResult(spans: [], literalRemainderOffset: units.isEmpty ? nil : 0)
        }
        for segment in segments {
            try Task.checkCancellation()
            var lexer = try MathSegmentLexer(units: units, segment: segment, identity: identity)
            let result = try lexer.scan(maximumSpanCount: maximumSpanCount - spans.count)
            spans.append(contentsOf: result.spans)
            if spans.count == maximumSpanCount {
                try Task.checkCancellation()
                return MathScanResult(spans: spans, literalRemainderOffset: result.end < units.count ? result.end : nil)
            }
        }
        try Task.checkCancellation()
        return MathScanResult(spans: spans, literalRemainderOffset: nil)
    }
}

private struct MathSegmentLexer {
    let units: [UInt16]
    let segment: Range<Int>
    let identity: MathSourceIdentity
    var display: MathDisplayDelimiterIndex

    init(units: [UInt16], segment: Range<Int>, identity: MathSourceIdentity) throws {
        self.units = units
        self.segment = segment
        self.identity = identity
        display = try MathDisplayDelimiterIndex(units: units, segment: segment)
    }

    mutating func scan(maximumSpanCount: Int) throws -> (spans: [MathSyntaxSpan], end: Int) {
        var spans: [MathSyntaxSpan] = []
        var cursor = segment.lowerBound
        var opening: Int?
        var slashes = 0
        var cancellationOffset = cursor
        while cursor < segment.upperBound {
            if cursor - cancellationOffset >= 4096 {
                try Task.checkCancellation()
                cancellationOffset = cursor
            }
            let unit = units[cursor]
            if unit == 92 {
                slashes += 1; cursor += 1; continue
            }
            let escaped = unit == 36 && slashes % 2 == 1
            slashes = 0
            if unit == 10 || unit == 13 {
                opening = nil
            }
            guard unit == 36, !escaped else { cursor += 1; continue }
            if cursor + 1 < segment.upperBound, units[cursor + 1] == 36 {
                opening = nil
                if let close = display.closingOffset(for: cursor, before: segment.upperBound) {
                    spans.append(span(cursor ..< close + 2, delimiter: 2))
                    cursor = close + 2
                } else {
                    cursor += 2 // unmatched display delimiters remain literal as a pair
                }
            } else {
                if let start = opening, closesInline(at: cursor, after: start) {
                    spans.append(span(start ..< cursor + 1, delimiter: 1))
                    opening = nil
                } else {
                    let next = MathSyntaxUnits.scalar(at: cursor + 1, in: units, before: segment.upperBound)
                    opening = next != nil && !MathSyntaxUnits.whitespace(next) ? cursor : nil
                }
                cursor += 1
            }
            if spans.count == maximumSpanCount {
                return (spans, cursor)
            }
        }
        return (spans, cursor)
    }

    private func closesInline(at closing: Int, after opening: Int) -> Bool {
        closing > opening + 1 &&
            !MathSyntaxUnits.whitespace(MathSyntaxUnits.scalar(
                before: closing,
                in: units,
                after: segment.lowerBound
            )) &&
            !MathSyntaxUnits.digit(MathSyntaxUnits.scalar(at: closing + 1, in: units, before: segment.upperBound))
    }

    private func span(_ full: Range<Int>, delimiter: Int) -> MathSyntaxSpan {
        let body = (full.lowerBound + delimiter) ..< (full.upperBound - delimiter)
        return MathSyntaxSpan(sourceIdentity: identity, fullRange: full, bodyRange: body,
                              expression: String(decoding: units[body], as: UTF16.self),
                              style: delimiter == 1 ? .inline : .display)
    }
}
