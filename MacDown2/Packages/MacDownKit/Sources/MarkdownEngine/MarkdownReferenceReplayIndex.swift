import Foundation

/// Selects parser-consumed definition syntax by proven original link/image uses.
/// Build once for a source snapshot; block lookup never rescans that whole source.
public struct MarkdownReferenceReplayIndex: Sendable {
    public enum Failure: Error { case sourceMismatch, invalidRange, partialReference, oversizedPrefix }

    public struct References: Sendable {
        public let links: [MarkdownSourceLink]
        public let images: [MarkdownSourceImage]
    }

    private struct Use: Sendable {
        let range: Range<Int>
        let definition: Int
    }

    public let sourceSHA256: String
    private let definitions: [MarkdownReferenceDefinition]
    private let uses: [Use]
    private let previousMaximumEnds: [Int]
    private let links: [MarkdownSourceLink]
    private let images: [MarkdownSourceImage]
    private let previousLinkEnds: [Int]
    private let previousImageEnds: [Int]

    public init(facts: MarkdownSourceFacts) throws {
        try Task.checkCancellation()
        var uses: [Use] = []
        for (index, definition) in facts.referenceDefinitions.enumerated() {
            for range in definition.useRanges {
                try Task.checkCancellation()
                guard !range.isEmpty, range.lowerBound >= 0 else { throw Failure.invalidRange }
                uses.append(Use(range: range, definition: index))
            }
        }
        try uses.sort {
            try Task.checkCancellation()
            return $0.range.lowerBound < $1.range.lowerBound
        }
        var maximum = 0
        var previous: [Int] = []
        for use in uses {
            try Task.checkCancellation()
            previous.append(maximum)
            maximum = max(maximum, use.range.upperBound)
        }
        previous.append(maximum)
        sourceSHA256 = facts.sourceSHA256
        definitions = facts.referenceDefinitions
        self.uses = uses
        previousMaximumEnds = previous
        links = try facts.links.sorted {
            try Task.checkCancellation()
            return $0.fullRange.lowerBound < $1.fullRange.lowerBound
        }
        images = try facts.images.sorted {
            try Task.checkCancellation()
            return $0.fullRange.lowerBound < $1.fullRange.lowerBound
        }
        previousLinkEnds = try Self.maximumEnds(links.map(\.fullRange))
        previousImageEnds = try Self.maximumEnds(images.map(\.fullRange))
    }

    /// Includes direct links/images as well as references. Query only the
    /// block's own intervals; no whole-document filtering or hashing per block.
    public func references(for range: Range<Int>, sourceSHA256: String) throws -> References {
        try Task.checkCancellation()
        guard self.sourceSHA256 == sourceSHA256 else { throw Failure.sourceMismatch }
        guard !range.isEmpty, range.lowerBound >= 0 else { throw Failure.invalidRange }
        return try References(
            links: Self.select(links, range: range, previousEnds: previousLinkEnds, originalRange: \.fullRange),
            images: Self.select(images, range: range, previousEnds: previousImageEnds, originalRange: \.fullRange)
        )
    }

    private static func maximumEnds(_ ranges: [Range<Int>]) throws -> [Int] {
        var result = [0]
        var maximum = 0
        for range in ranges {
            try Task.checkCancellation()
            guard !range.isEmpty, range.lowerBound >= 0 else { throw Failure.invalidRange }
            maximum = max(maximum, range.upperBound)
            result.append(maximum)
        }
        return result
    }

    private static func select<Item>(
        _ items: [Item], range: Range<Int>, previousEnds: [Int], originalRange: KeyPath<Item, Range<Int>>
    ) throws -> [Item] {
        try Task.checkCancellation()
        var low = 0, high = items.count
        while low < high {
            let middle = low + (high - low) / 2
            if items[middle][keyPath: originalRange].lowerBound < range.lowerBound {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard previousEnds[low] <= range.lowerBound else { throw Failure.partialReference }
        let start = low
        while low < items.count, items[low][keyPath: originalRange].lowerBound < range.upperBound {
            try Task.checkCancellation()
            guard items[low][keyPath: originalRange].upperBound <= range.upperBound
            else { throw Failure.partialReference }
            low += 1
        }
        return Array(items[start ..< low])
    }

    /// A caller's source anchor must match this snapshot. The byte allowance is
    /// for the prefix alone; its caller must also bound the complete expanded input.
    public func prefix(for range: Range<Int>, sourceSHA256: String, maximumUTF8Bytes: Int) throws -> String {
        try Task.checkCancellation()
        guard self.sourceSHA256 == sourceSHA256 else { throw Failure.sourceMismatch }
        guard !range.isEmpty, range.lowerBound >= 0 else { throw Failure.invalidRange }
        guard maximumUTF8Bytes >= 0 else { throw Failure.oversizedPrefix }
        let start = firstUse(atOrAfter: range.lowerBound)
        guard previousMaximumEnds[start] <= range.lowerBound else { throw Failure.partialReference }
        var selected = Set<Int>()
        var bytes = 0
        var index = start
        while index < uses.count, uses[index].range.lowerBound < range.upperBound {
            try Task.checkCancellation()
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
            try Task.checkCancellation()
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
