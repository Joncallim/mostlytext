import Foundation

/// Spans and prefixes advance together; no source rescan per equation/region.
struct MathExpressionProjection {
    struct Result {
        let expression: String
        let segments: [MathExpressionSourceSegment]
    }

    let units: [UInt16]
    let prefixes: [Range<Int>]
    private var prefixIndex = 0

    init(units: [UInt16], prefixes: [Range<Int>]) {
        self.units = units
        self.prefixes = prefixes
    }

    mutating func project(body: Range<Int>) throws -> Result {
        try Task.checkCancellation()
        guard body.lowerBound >= 0, body.upperBound <= units.count else { throw MathAnalysisError.invalidPrefixMapping }
        while prefixIndex < prefixes.count, prefixes[prefixIndex].upperBound <= body.lowerBound {
            if prefixIndex.isMultiple(of: 1024) {
                try Task.checkCancellation()
            }
            prefixIndex += 1
        }
        var cursor = body.lowerBound
        var rendered: [UInt16] = []
        var segments: [MathExpressionSourceSegment] = []
        rendered.reserveCapacity(body.count)
        func keep(_ range: Range<Int>) {
            guard !range.isEmpty else { return }
            let start = rendered.count
            rendered.append(contentsOf: units[range])
            segments.append(MathExpressionSourceSegment(renderedRange: start ..< rendered.count, sourceRange: range))
        }
        while prefixIndex < prefixes.count, prefixes[prefixIndex].lowerBound < body.upperBound {
            try Task.checkCancellation()
            let prefix = prefixes[prefixIndex]
            guard prefix.lowerBound >= cursor, prefix.upperBound <= body.upperBound
            else { throw MathAnalysisError.invalidPrefixMapping }
            keep(cursor ..< prefix.lowerBound)
            cursor = prefix.upperBound
            prefixIndex += 1
        }
        keep(cursor ..< body.upperBound)
        try Task.checkCancellation()
        return Result(expression: String(decoding: rendered, as: UTF16.self), segments: segments)
    }
}
