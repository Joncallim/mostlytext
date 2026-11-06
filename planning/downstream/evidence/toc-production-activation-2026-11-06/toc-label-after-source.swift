import Foundation
import MarkdownEngine

/// Replaces every line consisting only of `[TOC]` (surrounding whitespace
/// trimmed) with a nested Markdown list built from `document.headings`.
///
/// The list is plain text, not clickable links: no part of today's export
/// pipeline generates a stable `id` for a heading, and Preview hands every
/// link — anchor or not — to `NSWorkspace.shared.open` rather than
/// scrolling to it, so a link would not go anywhere useful in either
/// destination (epic-14-implementation.md §18, residual risk 2).
///
/// Zero headings still replaces the marker, with a short placeholder — the
/// literal text `[TOC]` never remains visible once a marker is found.
public struct TOCContribution: Contributing {
    public let id = "toc"

    public init() {}

    public func run(
        document: MarkdownDocument,
        sourceText: String,
        sourceGeneration: UInt
    ) async throws -> [ContributionResult] {
        let markers = Self.findMarkers(in: sourceText, document: document)
        guard !markers.isEmpty else { return [] }

        let list = Self.markdownList(for: document.headings)
        return markers.map { range in
            ContributionResult(
                contributionID: id,
                content: ContributionContent(sourceRange: range, placement: .block, representation: .markdown(list)),
                sourceGeneration: sourceGeneration
            )
        }
    }

    /// Every line whose trimmed content is exactly `[TOC]` AND that is
    /// semantically a top-level CommonMark paragraph, as the UTF-16 range of
    /// the whole physical line (trailing `\r` included, on a CRLF-terminated
    /// line) — never a zero-width point, since `[TOC]` itself is non-empty,
    /// satisfying `DerivedContentComposer`'s existing non-empty-range
    /// requirement by construction.
    ///
    /// A line lexically matching `[TOC]` inside fenced/indented code, a
    /// list item, a block quote, a heading, front matter, or an HTML block
    /// is literal text, not this contribution's syntax — checked against
    /// `document.blocks` (top-level parse blocks only) rather than a text
    /// scan, so Preview and Export can never disagree about which markers
    /// are "real" (epic-14-implementation.md architecture pass 3/10).
    static func findMarkers(in text: String, document: MarkdownDocument) -> [Range<Int>] {
        let sourceMap = document.sourceMap
        let nsText = text as NSString
        var ranges: [Range<Int>] = []
        var topLevelParagraphLines: Set<Int>?
        for line in 1 ... sourceMap.lineCount {
            let nsRange = sourceMap.utf16Range(ofLines: line ... line)
            let lineText = nsText.substring(with: nsRange)
            guard lineText.trimmingCharacters(in: .whitespacesAndNewlines) == "[TOC]" else { continue }
            // Built once, on the first candidate: a per-marker scan of every block was O(markers × blocks).
            let paragraphLines = topLevelParagraphLines ?? Self.topLevelParagraphLines(in: document.blocks)
            topLevelParagraphLines = paragraphLines
            guard paragraphLines.contains(line) else { continue }
            ranges.append(nsRange.location ..< (nsRange.location + nsRange.length))
        }
        return ranges
    }

    /// The lines that exactly one TOP-LEVEL block (no recursion into `children`) contains, where that block's kind
    /// is `.paragraph`. Deliberately not `document.block(atLine:)`: that helper recurses into children and would
    /// accept a paragraph nested inside a list item or block quote, both still literal/unsupported placement
    /// contexts for this first-party contribution.
    private static func topLevelParagraphLines(in topLevelBlocks: [MarkdownBlock]) -> Set<Int> {
        var owners: [Int: Int] = [:]
        var paragraphs: Set<Int> = []
        for block in topLevelBlocks {
            for line in block.lineRange {
                owners[line, default: 0] += 1
                if case .paragraph = block.kind {
                    paragraphs.insert(line)
                }
            }
        }
        return paragraphs.filter { owners[$0] == 1 }
    }

    /// Nests by heading level using 2-space Markdown list indentation (the
    /// minimum CommonMark requires to nest under a single-character `-`
    /// marker). A heading whose level skips ahead of its immediate
    /// predecessor (H1 directly followed by H3) is indented one level under
    /// the nearest shallower heading already seen, not clamped or rejected
    /// — a document's own heading structure is never "invalid" to this
    /// contribution.
    static func markdownList(for headings: [HeadingItem]) -> String {
        list(headings.map { (level: $0.level, content: escaped($0.title)) })
    }

    /// Serializes only an already-allocated index. The caller must first
    /// verify those fragments against the emitted HTML; `run` deliberately
    /// continues to produce the plain list until that end-to-end gate exists.
    static func linkedMarkdownList(for index: HeadingAnchorIndex) -> String {
        list(index.headings.map { heading in
            let destination = encodedFragment(heading.fragment)
            return (level: heading.level, content: "[\(escaped(heading.title))](#\(destination))")
        })
    }

    private static func list(_ entries: [(level: Int, content: String)]) -> String {
        guard !entries.isEmpty else {
            let message = String(localized: "No headings found.", bundle: .module)
            return "*(\(escaped(message)))*"
        }

        var lines: [String] = []
        var openLevels: [Int] = []
        for entry in entries {
            while let top = openLevels.last, top >= entry.level {
                openLevels.removeLast()
            }
            let indent = String(repeating: "  ", count: openLevels.count)
            openLevels.append(entry.level)
            lines.append("\(indent)- \(entry.content)")
        }
        return lines.joined(separator: "\n")
    }

    /// Encode the raw allocated ID once as a URL fragment destination. The
    /// Markdown renderer subsequently owns HTML attribute escaping.
    private static func encodedFragment(_ fragment: String) -> String {
        var result = ""
        for byte in fragment.utf8 {
            if (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || (byte >= 0x30 && byte <= 0x39) || [0x2D, 0x2E, 0x5F, 0x7E].contains(byte) {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    /// Backslash-escapes CommonMark's ASCII punctuation set. `title` is
    /// already plain text (markup stripped by swift-markdown) but can still
    /// contain characters — `[`, `*`, `#`, and similar — that would be
    /// re-interpreted as syntax once re-embedded in this newly generated
    /// list; backslash-escaping is valid anywhere in CommonMark and has no
    /// effect beyond presenting the literal character, so escaping every
    /// occurrence is always safe. Work by scalar: a Prepend or combining mark
    /// must not hide an ASCII punctuation token inside a larger Character.
    private static func escaped(_ title: String) -> String {
        var result = ""
        result.reserveCapacity(title.count)
        for scalar in title.unicodeScalars {
            let value = scalar.value
            if (0x21 ... 0x2F).contains(value) || (0x3A ... 0x40).contains(value) ||
                (0x5B ... 0x60).contains(value) || (0x7B ... 0x7E).contains(value) {
                result.append("\\")
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}
