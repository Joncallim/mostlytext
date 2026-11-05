import Foundation

struct MathDisplayDelimiterIndex {
    private struct Entry {
        let offset: Int
        let generation: Int
    }

    private let entries: [Entry]
    private var openingIndex = 0
    private var closingIndex = 0

    init(units: [UInt16], segment: Range<Int>) throws {
        var entries: [Entry] = []
        var generation = 0
        var slashes = 0
        var cursor = segment.lowerBound
        var cancellationOffset = cursor
        while cursor < segment.upperBound {
            if cursor - cancellationOffset >= 4096 {
                try Task.checkCancellation()
                cancellationOffset = cursor
            }
            let terminator = MathSyntaxUnits.terminatorLength(at: cursor, in: units, before: segment.upperBound)
            if terminator > 0 {
                if MathSyntaxUnits.blankLine(at: cursor, in: units, before: segment.upperBound) {
                    generation += 1
                }
                cursor += terminator
                slashes = 0
                continue
            }
            let unit = units[cursor]
            if unit == 92 {
                slashes += 1
            } else {
                if unit == 36, slashes % 2 == 0, cursor + 1 < segment.upperBound, units[cursor + 1] == 36 {
                    entries.append(Entry(offset: cursor, generation: generation))
                }
                slashes = 0
            }
            cursor += 1
        }
        self.entries = entries
    }

    mutating func closingOffset(for opening: Int, before end: Int) -> Int? {
        guard end - opening >= 5 else { return nil }
        while openingIndex < entries.count, entries[openingIndex].offset < opening {
            openingIndex += 1
        }
        guard openingIndex < entries.count, entries[openingIndex].offset == opening else { return nil }
        while closingIndex < entries.count, entries[closingIndex].offset < opening + 3 {
            closingIndex += 1
        }
        guard closingIndex < entries.count,
              entries[closingIndex].generation == entries[openingIndex].generation
        else { return nil }
        return entries[closingIndex].offset
    }
}
