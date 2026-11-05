import Foundation

/// Selects parser-consumed definition syntax by proven original link/image uses.
/// Build once for a source snapshot; block lookup never rescans that whole source.
public struct MarkdownReferenceReplayIndex: Sendable {
    public enum Failure: Error { case sourceMismatch, invalidRange, partialReference, oversizedPrefix }

    private struct Use: Sendable {
        let range: Range<Int>
        let definition: Int
    }

    public let sourceSHA256: String
    private let definitions: [MarkdownReferenceDefinition]
    private let uses: [Use]
    private let previousMaximumEnds: [Int]

    public init(facts: MarkdownSourceFacts) throws {
        var uses: [Use] = []
        for (index, definition) in facts.referenceDefinitions.enumerated() {
            for range in definition.useRanges {
                guard !range.isEmpty, range.lowerBound >= 0 else { throw Failure.invalidRange }
                uses.append(Use(range: range, definition: index))
            }
        }
        uses.sort { $0.range.lowerBound < $1.range.lowerBound }
        var maximum = 0
        var previous: [Int] = []
        for use in uses {
            previous.append(maximum)
            maximum = max(maximum, use.range.upperBound)
        }
        previous.append(maximum)
        sourceSHA256 = facts.sourceSHA256
        definitions = facts.referenceDefinitions
        self.uses = uses
        previousMaximumEnds = previous
    }

    /// A caller's source anchor must match this snapshot. The byte allowance is
    /// for the prefix alone; its caller must also bound the complete expanded input.
    public func prefix(for range: Range<Int>, sourceSHA256: String, maximumUTF8Bytes: Int) throws -> String {
        guard self.sourceSHA256 == sourceSHA256 else { throw Failure.sourceMismatch }
        guard !range.isEmpty, range.lowerBound >= 0 else { throw Failure.invalidRange }
        guard maximumUTF8Bytes >= 0 else { throw Failure.oversizedPrefix }
        let start = firstUse(atOrAfter: range.lowerBound)
        guard previousMaximumEnds[start] <= range.lowerBound else { throw Failure.partialReference }
        var selected = Set<Int>()
        var bytes = 0
        var index = start
        while index < uses.count, uses[index].range.lowerBound < range.upperBound {
            let use = uses[index]
            guard use.range.upperBound <= range.upperBound else { throw Failure.partialReference }
            if selected.insert(use.definition).inserted {
                let size = definitions[use.definition].source.utf8.count
                guard size <= maximumUTF8Bytes - bytes, maximumUTF8Bytes - bytes - size >= 2 else {
                    throw Failure.oversizedPrefix
                }
                bytes += size + 2
            }
            index += 1
        }
        var prefix = ""
        prefix.reserveCapacity(bytes)
        for selectedIndex in selected.sorted() {
            prefix += definitions[selectedIndex].source
            prefix += "\n\n"
        }
        return prefix
    }

    private func firstUse(atOrAfter offset: Int) -> Int {
        var low = 0, high = uses.count
        while low < high {
            let middle = low + (high - low) / 2
            if uses[middle].range.lowerBound < offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
