import Foundation

/// Exact original-source facts exported by the sole Markdown parser, never an AST.
public struct MarkdownSourceFacts: Sendable, Equatable {
    public let sourceSHA256: String
    public let inlineRegions: [Range<Int>]
    public let literalRanges: [Range<Int>]
    public let continuationPrefixes: [Range<Int>]
    public let links: [MarkdownSourceLink]
}

public struct MarkdownSourceLink: Sendable, Equatable {
    public let fullRange: Range<Int>
    public let labelRange: Range<Int>?
    public let destination: String?
    public let title: String?
    /// Original, undecoded key for a full, collapsed or shortcut reference.
    /// Nil for an inline destination or angle-bracket autolink.
    public let referenceKey: String?
}

/// Parser coordinates count one-based UTF-8 byte columns, not UTF-16 or graphemes.
struct MarkdownSourcePoint: Sendable, Hashable, Comparable {
    let line: Int
    let column: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.line == rhs.line ? lhs.column < rhs.column : lhs.line < rhs.line
    }
}

struct MarkdownSourceNode {
    enum Kind {
        case container, inline, lineBreak, literal, opaque, other
        case link(destination: String?, title: String?)
    }

    let kind: Kind
    let range: Range<MarkdownSourcePoint>?
}

/// Resolves only requested scalar boundaries in one source pass and one sort.
/// There is no per-byte index, NSString search, or newline normalization.
enum MarkdownSourceCoordinates {
    static func resolve(_ points: Set<MarkdownSourcePoint>, in source: String) -> [MarkdownSourcePoint: Int]? {
        if points.isEmpty {
            return [:]
        }
        let ordered = points.sorted()
        var result: [MarkdownSourcePoint: Int] = [:]
        var index = 0
        var line = 1
        var column = 1
        var offset = 0
        var pendingCR = false
        func record() -> Bool {
            let point = MarkdownSourcePoint(line: line, column: column)
            if index < ordered.count, ordered[index] < point {
                return false
            }
            if index < ordered.count, ordered[index] == point {
                result[point] = offset
                index += 1
            }
            return true
        }
        for scalar in source.unicodeScalars {
            if pendingCR {
                line += 1; column = 1; pendingCR = false
                if scalar.value == 10 {
                    offset += 1; continue
                }
            }
            guard record() else { return nil }
            offset += scalar.utf16.count
            switch scalar.value {
            case 13: pendingCR = true
            case 10: line += 1; column = 1
            default: column += scalar.utf8.count
            }
        }
        if pendingCR {
            line += 1; column = 1
        }
        guard record(), index == ordered.count else { return nil }
        return result
    }
}
