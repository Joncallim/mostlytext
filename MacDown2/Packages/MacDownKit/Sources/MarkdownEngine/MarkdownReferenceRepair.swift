import Foundation

/// Preserves original implicit reference identity when a consumer replaces part
/// of a resolved link label. It never synthesizes a destination or definition.
public enum MarkdownReferenceRepair {
    public struct Edit: Sendable, Equatable {
        public let sourceRange: Range<Int>
        public let replacement: String

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.sourceRange == rhs.sourceRange && lhs.replacement.utf8.elementsEqual(rhs.replacement.utf8)
        }
    }

    public enum Failure: Error, Equatable {
        case sourceMismatch
        case invalidRange
        case invalidReferenceSyntax
    }

    /// Coordinates and links must come from this exact original-source parse.
    /// Only accepted replacements fully inside a label can request a repair.
    public static func edits(
        source: String, facts: MarkdownSourceFacts, replacing ranges: [Range<Int>]
    ) throws -> [Edit] {
        try Task.checkCancellation()
        guard MarkdownSourceFingerprint.sha256(source) == facts.sourceSHA256 else { throw Failure.sourceMismatch }
        try Task.checkCancellation()
        let units = Array(source.utf16)
        for range in ranges {
            try Task.checkCancellation()
            try validate(range, units: units)
        }
        let sorted = try ranges.sorted {
            try Task.checkCancellation()
            return $0.lowerBound < $1.lowerBound
        }
        for index in sorted.indices.dropFirst() where sorted[index - 1].upperBound > sorted[index].lowerBound {
            throw Failure.invalidRange
        }
        var result: [Edit] = []
        var cursor = 0
        for link in facts.links {
            try Task.checkCancellation()
            guard let label = link.labelRange, let key = link.referenceKey else { continue }
            while cursor < sorted.count, sorted[cursor].upperBound <= label.lowerBound {
                cursor += 1
            }
            guard sorted[cursor...].prefix(while: { $0.lowerBound < label.upperBound }).contains(where: {
                $0.lowerBound >= label.lowerBound && $0.upperBound <= label.upperBound
            }) else { continue }
            try validate(link.fullRange, units: units)
            try validate(label, units: units)
            guard label.upperBound < link.fullRange.upperBound else { throw Failure.invalidReferenceSyntax }
            let suffix = label.upperBound ..< link.fullRange.upperBound
            let ending = String(decoding: units[suffix], as: UTF16.self)
            guard ending == "]" || ending == "][]"
            else { continue } // Full keys and inline destinations are independent.
            guard String(decoding: units[label], as: UTF16.self).utf8.elementsEqual(key.utf8) else {
                throw Failure.invalidReferenceSyntax
            }
            let originalKey = try projectedKey(label, units: units, prefixes: facts.continuationPrefixes)
            result.append(Edit(sourceRange: suffix, replacement: "][" + originalKey + "]"))
            result.append(contentsOf: literalBacktickEdits(label: label, units: units,
                                                           literals: facts.literalRanges, replacements: sorted))
        }
        return try result.sorted {
            try Task.checkCancellation()
            return $0.sourceRange.lowerBound < $1.sourceRange.lowerBound
        }
    }

    private static func projectedKey(
        _ label: Range<Int>, units: [UInt16], prefixes: [Range<Int>]
    ) throws -> String {
        var result = ""
        var cursor = label.lowerBound
        var low = 0, high = prefixes.count
        while low < high {
            let middle = low + (high - low) / 2
            if prefixes[middle].upperBound <= label.lowerBound {
                low = middle + 1
            } else {
                high = middle
            }
        }
        for prefix in prefixes[low...].prefix(while: { $0.lowerBound < label.upperBound }) {
            try validate(prefix, units: units)
            guard prefix.lowerBound >= cursor, prefix.upperBound <= label.upperBound else {
                throw Failure.invalidReferenceSyntax
            }
            result += String(decoding: units[cursor ..< prefix.lowerBound], as: UTF16.self)
            cursor = prefix.upperBound
        }
        result += String(decoding: units[cursor ..< label.upperBound], as: UTF16.self)
        return result
    }

    private static func validate(_ range: Range<Int>, units: [UInt16]) throws {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= units.count,
              boundary(range.lowerBound, units: units), boundary(range.upperBound, units: units) else {
            throw Failure.invalidRange
        }
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
