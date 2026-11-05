import Foundation

/// The AST supplies authority and resolved targets. Original bracket syntax
/// supplies identity; a destination-equals-label heuristic cannot do that.
enum MarkdownSourceLinkProjection {
    static func project(
        range: Range<Int>, units: [UInt16], literals: [Range<Int>], destination: String?, title: String?
    ) -> MarkdownSourceLink? {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= units.count else { return nil }
        if units[range.lowerBound] == 60 {
            return MarkdownSourceLink(fullRange: range, labelRange: nil, destination: destination,
                                      title: title, referenceKey: nil)
        }
        guard units[range.lowerBound] == 91,
              let close = closingBracket(
                  after: range.lowerBound,
                  before: range.upperBound,
                  units: units,
                  literals: literals
              )
        else { return nil }
        let label = (range.lowerBound + 1) ..< close
        let suffix = close + 1
        let key: String?
        if suffix == range.upperBound {
            key = String(decoding: units[label], as: UTF16.self)
        } else if units[suffix] == 40 {
            key = nil
        } else if units[suffix] == 91,
                  let end = closingBracket(after: suffix, before: range.upperBound, units: units, literals: literals),
                  end + 1 == range.upperBound {
            let explicit = (suffix + 1) ..< end
            key = String(decoding: units[explicit.isEmpty ? label : explicit], as: UTF16.self)
        } else {
            return nil
        }
        return MarkdownSourceLink(fullRange: range, labelRange: label, destination: destination,
                                  title: title, referenceKey: key)
    }

    private static func closingBracket(after opening: Int, before end: Int, units: [UInt16],
                                       literals: [Range<Int>]) -> Int? {
        var depth = 1
        var cursor = opening + 1
        var low = 0
        var high = literals.count
        while low < high {
            let middle = low + (high - low) / 2
            if literals[middle].upperBound <= opening {
                low = middle + 1
            } else {
                high = middle
            }
        }
        var literal = low
        while cursor < end {
            while literal < literals.count, literals[literal].upperBound <= cursor {
                literal += 1
            }
            if literal < literals.count, literals[literal].contains(cursor) {
                cursor = literals[literal].upperBound
                continue
            }
            if units[cursor] == 92 {
                cursor += min(2, end - cursor); continue
            }
            if units[cursor] == 91 {
                depth += 1
            }
            if units[cursor] == 93 {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor += 1
        }
        return nil
    }
}
