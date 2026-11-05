import Foundation

/// Generic only to keep upstream AST types inside ParseEngine.swift. These
/// synchronous closures cannot retain or export a parser node to a consumer.
enum MarkdownSourceFactProjection {
    private struct Pending<Node> {
        let node: Node
        let container: Int?
        let depth: Int
    }

    private struct RawLink {
        let range: Range<MarkdownSourcePoint>
        let destination: String?
        let title: String?
    }

    private struct RawFacts {
        var containers: [[Range<MarkdownSourcePoint>]] = []
        var literals: [Range<MarkdownSourcePoint>] = []
        var links: [RawLink] = []

        var ranges: [Range<MarkdownSourcePoint>] {
            containers.flatMap(\.self) + literals + links.map(\.range)
        }
    }

    static func project<Node>(
        source: String, sourceSHA256: String, root: Node,
        referenceDefinitions: [MarkdownSourceReferenceDefinition] = [],
        children: (Node) -> [Node], describe: (Node) -> MarkdownSourceNode
    ) -> MarkdownSourceFacts? {
        guard let raw = collect(root: root, children: children, describe: describe) else { return nil }
        let ranges = raw.ranges + referenceDefinitions.flatMap(\.useRanges)
        let points = Set(ranges.flatMap { [$0.lowerBound, $0.upperBound] })
        guard let offsets = MarkdownSourceCoordinates.resolve(points, in: source) else { return nil }
        func convert(_ range: Range<MarkdownSourcePoint>) -> Range<Int>? {
            guard let lower = offsets[range.lowerBound], let upper = offsets[range.upperBound], lower <= upper
            else { return nil }
            return lower ..< upper
        }
        let units = Array(source.utf16)
        guard let containers = resolveContainers(
            raw.containers,
            source: source,
            units: units,
            offsets: offsets,
            convert: convert
        )
        else { return nil }
        let literals = raw.literals.compactMap(convert).sorted { $0.lowerBound < $1.lowerBound }
        var links: [MarkdownSourceLink] = []
        for link in raw.links {
            guard let range = convert(link.range),
                  let resolved = MarkdownSourceLinkProjection.project(
                      range: range, units: units, literals: literals, destination: link.destination, title: link.title
                  ) else { return nil }
            links.append(resolved)
        }
        guard let definitions = resolveReferences(referenceDefinitions, convert: convert) else { return nil }
        return MarkdownSourceFacts(
            sourceSHA256: sourceSHA256, inlineRegions: containers.regions, literalRanges: literals,
            continuationPrefixes: containers.prefixes,
            links: links.sorted { $0.fullRange.lowerBound < $1.fullRange.lowerBound },
            referenceDefinitions: definitions
        )
    }

    private static func resolveReferences(
        _ references: [MarkdownSourceReferenceDefinition], convert: (Range<MarkdownSourcePoint>) -> Range<Int>?
    ) -> [MarkdownReferenceDefinition]? {
        var result: [MarkdownReferenceDefinition] = []
        for reference in references {
            var uses: [Range<Int>] = []
            for original in reference.useRanges {
                guard let range = convert(original), !range.isEmpty else { return nil }
                uses.append(range)
            }
            result.append(MarkdownReferenceDefinition(source: reference.source, useRanges: uses))
        }
        return result
    }

    private static func collect<Node>(
        root: Node, children: (Node) -> [Node], describe: (Node) -> MarkdownSourceNode
    ) -> RawFacts? {
        var pending = [Pending(node: root, container: nil, depth: 0)]
        var raw = RawFacts()
        while let item = pending.popLast() {
            guard item.depth <= 128 else { return nil }
            let node = describe(item.node)
            var container = item.container
            guard append(node, container: &container, raw: &raw) else { return nil }
            switch node.kind {
            case .opaque, .literal: continue
            default: break
            }
            for child in children(item.node).reversed() {
                pending.append(Pending(node: child, container: container, depth: item.depth + 1))
            }
        }
        return raw
    }

    private static func append(_ node: MarkdownSourceNode, container: inout Int?, raw: inout RawFacts) -> Bool {
        switch node.kind {
        case .container:
            container = raw.containers.count
            raw.containers.append([])
        case .inline, .literal, .link:
            guard let range = node.range else { return false }
            if let container {
                raw.containers[container].append(range)
            }
            if case .literal = node.kind {
                raw.literals.append(range)
            }
            if case let .link(destination, title) = node.kind {
                raw.links.append(RawLink(range: range, destination: destination, title: title))
            }
        case .opaque, .lineBreak, .other: break
        }
        return true
    }

    private static func resolveContainers(
        _ containers: [[Range<MarkdownSourcePoint>]], source: String, units: [UInt16],
        offsets: [MarkdownSourcePoint: Int],
        convert: (Range<MarkdownSourcePoint>) -> Range<Int>?
    ) -> (regions: [Range<Int>], prefixes: [Range<Int>])? {
        let sourceMap = SourceMap(text: source)
        var regions: [Range<Int>] = []
        var prefixes: [Range<Int>] = []
        for container in containers where !container.isEmpty {
            guard let lower = container.map(\.lowerBound).min(), let upper = container.map(\.upperBound).max(),
                  let region = convert(lower ..< upper),
                  let continuation = continuationPrefixes(container, firstLine: lower.line,
                                                          sourceMap: sourceMap, units: units, offsets: offsets)
            else { return nil }
            regions.append(region)
            prefixes.append(contentsOf: continuation)
        }
        regions.sort { $0.lowerBound < $1.lowerBound }
        for index in regions.indices.dropFirst() {
            guard regions[index - 1].upperBound <= regions[index].lowerBound else { return nil }
        }
        return (regions, Array(Set(prefixes)).sorted { $0.lowerBound < $1.lowerBound })
    }

    private static func continuationPrefixes(
        _ container: [Range<MarkdownSourcePoint>], firstLine: Int,
        sourceMap: SourceMap, units: [UInt16], offsets: [MarkdownSourcePoint: Int]
    ) -> [Range<Int>]? {
        var starts: [Int: MarkdownSourcePoint] = [:]
        for range in container where range.lowerBound.line > firstLine {
            let point = range.lowerBound
            starts[point.line] = min(starts[point.line] ?? point, point)
        }
        var prefixes: [Range<Int>] = []
        for (line, point) in starts {
            guard line > 0, line <= sourceMap.lineCount, let end = offsets[point] else { return nil }
            let start = sourceMap.lineStartOffsets[line - 1]
            // A later node can follow a multiline link destination/title. That
            // authored syntax is not a removable container prefix.
            if start < end, units[start ..< end].allSatisfy({ $0 == 32 || $0 == 9 || $0 == 62 }) {
                prefixes.append(start ..< end)
            }
        }
        return prefixes
    }
}
