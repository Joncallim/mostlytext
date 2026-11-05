import CryptoKit
import Foundation
import MarkdownEngine

/// One preview-renderable slice of a Markdown document.
///
/// ``PreviewBlock`` mirrors a top-level ``MarkdownBlock`` but carries the
/// original Markdown source for that block. Rendering blocks individually lets
/// the preview map editor source lines to preview geometry for scroll sync.
///
/// Blocks built by ``blocks(from:text:)`` derive their ``id`` deterministically
/// from the block's source and line range, so SwiftUI view identity stays
/// stable while the document is unchanged. Random IDs would churn `ForEach`
/// identity on every body evaluation, resetting per-block view state (and the
/// scroll-sync frame lookup) each time.
public struct PreviewBlock: Sendable, Equatable, Identifiable {
    /// Byte threshold above which a block degrades to plain text instead of
    /// reaching Textual. Textual 0.5.0 has no size limit of its own and is
    /// documented to freeze/crash on inputs around 100 KB
    /// (gonzalezreal/textual#23, #47); slicing by top-level block only bounds
    /// the common case; a single large fenced code block, unbroken paragraph,
    /// or big table/HTML block can still reach that size on its own.
    public static let oversizeByteThreshold = PreviewParserBudget.maximumUTF8Bytes

    public let id: UUID
    public let kind: BlockKind
    public let source: String
    public let lineRange: ClosedRange<Int>
    public let sourceAnchor: SourceAnchor?

    /// Only the exact-source slicer creates an origin. Generated content can
    /// carry no such origin merely because it looks like the author's text.
    public struct SourceAnchor: Sendable, Equatable {
        public let sourceSHA256: String
        public let range: Range<Int>

        /// The contribution composer may retain authority for unchanged source.
        public func slice(_ range: Range<Int>) -> Self? {
            guard !range.isEmpty, range.lowerBound >= self.range.lowerBound,
                  range.upperBound <= self.range.upperBound else { return nil }
            return Self(sourceSHA256: sourceSHA256, range: range)
        }
    }

    /// `true` when `source` exceeds ``oversizeByteThreshold``. Callers should
    /// render an oversize block as plain text rather than handing it to
    /// Textual.
    public let isOversize: Bool

    public init(
        id: UUID = UUID(),
        kind: BlockKind,
        source: String,
        lineRange: ClosedRange<Int>,
        sourceAnchor: SourceAnchor? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.lineRange = lineRange
        self.sourceAnchor = sourceAnchor?.range.count == source.utf16.count ? sourceAnchor : nil
        isOversize = source.utf8.count > Self.oversizeByteThreshold
    }
}

public extension PreviewBlock {
    /// Builds preview blocks from a parsed document and the original source text.
    ///
    /// `text` must be the exact source that produced `document` (i.e.
    /// ``MarkdownParseSession/publishedText``). The source for each top-level
    /// block is extracted via the document's ``SourceMap``.
    static func blocks(from document: MarkdownDocument, text: String) -> [PreviewBlock] {
        let sourceMap = document.sourceMap
        let original = text as NSString
        // Validate once for the whole snapshot, never once per block.
        let fingerprint = document.isBound(to: text) ? document.sourceSHA256 : nil
        guard original.length == sourceMap.utf16Length else {
            let fallback = PreviewBlock(
                kind: .paragraph,
                source: text,
                lineRange: 1 ... max(1, SourceMap(text: text).lineCount)
            )
            return [fallback]
        }
        return document.blocks.map { block in
            let range = sourceMap.utf16Range(ofLines: block.lineRange)
            let substring = original.substring(with: range)
            return PreviewBlock(
                id: stableID(source: substring, lineRange: block.lineRange),
                kind: block.kind,
                source: substring,
                lineRange: block.lineRange,
                sourceAnchor: fingerprint.map { SourceAnchor(
                    sourceSHA256: $0,
                    range: range.location ..< NSMaxRange(range)
                ) }
            )
        }
    }

    /// A deterministic identifier derived from the block's content and
    /// position. Line ranges are disjoint within a document, so IDs are
    /// unique per block and stable across re-evaluations of the same text.
    private static func stableID(source: String, lineRange: ClosedRange<Int>) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Data("\(lineRange.lowerBound):\(lineRange.upperBound)\n".utf8))
        hasher.update(data: Data(source.utf8))
        let bytes = Array(hasher.finalize().prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
