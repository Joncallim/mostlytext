import Foundation

extension MarkdownReferenceRepair {
    /// Copying a raw implicit key can introduce the closing backtick for an
    /// originally unmatched literal opener in the visible label. Protect only
    /// that literal spelling; actual code/HTML and replacement spans stay intact.
    static func literalBacktickEdits(
        label: Range<Int>, units: [UInt16], literals: [Range<Int>], replacements: [Range<Int>]
    ) -> [Edit] {
        let blocked = (overlapping(literals, label: label) + overlapping(replacements, label: label))
            .sorted { $0.lowerBound < $1.lowerBound }
        var index = label.lowerBound
        var blockIndex = 0
        var backslashes = 0
        var edits: [Edit] = []
        while index < label.upperBound {
            if blockIndex < blocked.count, blocked[blockIndex].lowerBound <= index {
                index = max(index, blocked[blockIndex].upperBound)
                blockIndex += 1
                backslashes = 0
                continue
            }
            let unit = units[index]
            if unit == 96, backslashes.isMultiple(of: 2) {
                edits.append(Edit(sourceRange: index ..< (index + 1), replacement: "\\`"))
            }
            backslashes = unit == 92 ? backslashes + 1 : 0
            index += 1
        }
        return edits
    }

    private static func overlapping(_ ranges: [Range<Int>], label: Range<Int>) -> [Range<Int>] {
        var low = 0, high = ranges.count
        while low < high {
            let middle = low + (high - low) / 2
            if ranges[middle].upperBound <= label.lowerBound {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return Array(ranges[low...].prefix { $0.lowerBound < label.upperBound })
    }
}
