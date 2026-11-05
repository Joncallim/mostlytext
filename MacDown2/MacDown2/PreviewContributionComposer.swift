import Contributions
import CryptoKit
import Foundation
import MarkdownEngine
import Preview

/// Source-ordered block composition and deterministic fragment IDs
/// (architecture takeover, "Source-ordered block composition" /
/// "Deterministic IDs for affected blocks"). `CryptoKit` is a system
/// framework imported only here — no new SPM dependency, and no exposure of
/// `Preview`'s own package-private ID helper.
extension PreviewContributionAdapter {
    /// Rebuilds `base` with every accepted candidate spliced in, in source
    /// order. Returns `nil` when the result would violate the ordered/
    /// non-overlapping invariant `TextualMarkdownPreview`/`ScrollSyncMap`
    /// depend on — the caller falls back to `base` unchanged in that case.
    static func composeBlocks(
        base: [PreviewBlock],
        baseIntervals: [Range<Int>],
        accepted: [PreviewContributionCandidate],
        sourceText: String,
        sourceMap: SourceMap
    ) -> [PreviewBlock]? {
        guard !accepted.isEmpty else { return base }

        let byBlock = Dictionary(grouping: accepted, by: \.containingBlockIndex)
        let nsSource = sourceText as NSString
        var usedIDKeys = Set<String>()
        var result: [PreviewBlock] = []

        for (index, block) in base.enumerated() {
            guard let placements = byBlock[index], !placements.isEmpty else {
                result.append(block)
                continue
            }
            let ordered = placements.sorted { $0.sourceRange.lowerBound < $1.sourceRange.lowerBound }
            var assembler = FragmentAssembler(blockInterval: baseIntervals[index], nsSource: nsSource)
            for placement in ordered {
                assembler.apply(placement)
            }
            for fragment in assembler.finish() {
                result.append(previewBlock(
                    for: fragment,
                    containingBlock: block,
                    sourceMap: sourceMap,
                    usedIDKeys: &usedIDKeys
                ))
            }
        }

        guard isOrderedAndNonOverlapping(result) else { return nil }
        return result
    }

    private static func previewBlock(
        for fragment: PreviewContributionFragment,
        containingBlock: PreviewBlock,
        sourceMap: SourceMap,
        usedIDKeys: inout Set<String>
    ) -> PreviewBlock {
        let lowerLine = sourceMap.line(atUTF16Offset: fragment.range.lowerBound)
        let upperLine = sourceMap.line(atUTF16Offset: fragment.range.upperBound - 1)
        let kind = fragment.contributionID.map(BlockKind.custom) ?? containingBlock.kind
        let id = deterministicID(baseBlockID: containingBlock.id, fragment: fragment, usedKeys: &usedIDKeys)
        let anchor = fragment.role == .authored ? containingBlock.sourceAnchor?.slice(fragment.range) : nil
        return PreviewBlock(id: id, kind: kind, source: fragment.text,
                            lineRange: lowerLine ... upperLine, sourceAnchor: anchor)
    }

    /// Requires strictly increasing, non-touching integer line ranges —
    /// consecutive top-level blocks (and their split-out fragments) can
    /// never share a line.
    private static func isOrderedAndNonOverlapping(_ blocks: [PreviewBlock]) -> Bool {
        var previousUpperBound = 0
        for block in blocks {
            guard block.lineRange.lowerBound >= previousUpperBound else { return false }
            previousUpperBound = block.lineRange.upperBound + 1
        }
        return true
    }

    /// A private app-side UUID derived from a stable serialization of the
    /// fragment's identity — never `Hasher`/`hashValue`/a random default
    /// `UUID()`, so re-rendering the same snapshot returns equal IDs.
    private static func deterministicID(
        baseBlockID: UUID,
        fragment: PreviewContributionFragment,
        usedKeys: inout Set<String>
    ) -> UUID {
        let baseKey = "\(baseBlockID.uuidString)|\(fragment.role.rawValue)|"
            + "\(fragment.range.lowerBound)|\(fragment.range.upperBound)|\(fragment.contributionID ?? "")"
        var key = baseKey
        var ordinal = 0
        while usedKeys.contains(key) {
            ordinal += 1
            key = "\(baseKey)|\(ordinal)"
        }
        usedKeys.insert(key)

        var hasher = SHA256()
        hasher.update(data: Data(key.utf8))
        let bytes = Array(hasher.finalize().prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Walks one affected base block's accepted placements left to right with a
/// UTF-16 cursor, splicing inline replacements into an authored buffer and
/// flushing that buffer around each block placement.
private struct FragmentAssembler {
    private let blockInterval: Range<Int>
    private let nsSource: NSString
    private var fragments: [PreviewContributionFragment] = []
    private var cursor: Int
    private var bufferStart: Int
    private var buffer = ""
    private var bufferHasInline = false

    init(blockInterval: Range<Int>, nsSource: NSString) {
        self.blockInterval = blockInterval
        self.nsSource = nsSource
        cursor = blockInterval.lowerBound
        bufferStart = blockInterval.lowerBound
    }

    mutating func apply(_ placement: PreviewContributionCandidate) {
        appendLiteral(upTo: placement.sourceRange.lowerBound)
        switch placement.placement {
        case .inline:
            buffer += placement.markdown
            bufferHasInline = true
            cursor = placement.sourceRange.upperBound
        case .block:
            flush(upTo: placement.sourceRange.lowerBound)
            fragments.append(PreviewContributionFragment(
                role: .generated, text: placement.markdown,
                range: placement.sourceRange, contributionID: placement.contributionID
            ))
            cursor = placement.sourceRange.upperBound
            consumeTrailingLineTerminator()
            bufferStart = cursor
        }
    }

    mutating func finish() -> [PreviewContributionFragment] {
        appendLiteral(upTo: blockInterval.upperBound)
        flush(upTo: blockInterval.upperBound)
        return fragments
    }

    private mutating func appendLiteral(upTo end: Int) {
        guard end > cursor else { return }
        buffer += nsSource.substring(with: NSRange(location: cursor, length: end - cursor))
        cursor = end
    }

    /// `SourceMap` line ranges end before the line's whole terminator (`\n`,
    /// `\r\n` or a lone `\r`), so exactly that one terminator — never the
    /// authored content after it — sits between a block placement's upper
    /// bound and whatever follows.
    private mutating func consumeTrailingLineTerminator() {
        guard cursor < blockInterval.upperBound else { return }
        let unit = nsSource.character(at: cursor)
        guard unit == 0x000A || unit == 0x000D else { return }
        cursor += 1
        if unit == 0x000D, cursor < blockInterval.upperBound, nsSource.character(at: cursor) == 0x000A {
            cursor += 1
        }
    }

    private mutating func flush(upTo end: Int) {
        defer {
            buffer = ""
            bufferStart = end
            bufferHasInline = false
        }
        guard bufferStart < end, !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        fragments.append(PreviewContributionFragment(
            role: bufferHasInline ? .inlineComposed : .authored,
            text: buffer, range: bufferStart ..< end, contributionID: nil
        ))
    }
}
