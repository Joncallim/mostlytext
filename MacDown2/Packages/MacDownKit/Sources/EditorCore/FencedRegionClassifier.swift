import Foundation

// MARK: - Fenced-code/front-matter classification (EPIC-22 §2.3, §6.12, §7.3, Slice 4b)

/// Bounded, local, synchronous classifier for whether a UTF-16 offset sits
/// inside a fenced code block, YAML front matter, or ordinary prose. Never
/// touches `MarkdownEngine`/`SourceMap` (E10's own "no full parse on the hot
/// path" rule, §2.1) — this is a plain `NSString` scan, closing the E10
/// inherited-debt item §2.3 named.
///
/// See §6.12 for the full design reasoning this type implements, including
/// why a bounded backward scan can only be exact up to a finite cap (it is
/// exact for the overwhelming majority of real documents, which are far
/// smaller than that cap) and why fence-line detection here is a practical,
/// disclosed approximation of CommonMark's own grammar rather than a second
/// Markdown parser.
///
/// Two further disclosed simplifications (found by an independent review,
/// alongside the 4-space-indent and blockquote-nesting limitations already
/// pinned by tests below): this classifier counts ANY fence-delimiter line
/// as toggling in/out of a fenced region, without checking (1) that a
/// closing line's marker CHARACTER matches the opener's (real CommonMark
/// requires a ` ``` ` fence to be closed only by another ` ``` ` line, never
/// by `~~~`, and vice versa — see
/// `mismatchedFenceCharactersAreTreatedAsClosingAnyOpenFence` below, which
/// pins the current, simplified behavior), or (2) that a closing line's
/// marker is at least as LONG as its opener's (real CommonMark requires a
/// 4-backtick opener to be closed by 4+ backticks, not merely 3 — this
/// classifier accepts any 3+ run as a valid closer for any opener). Both are
/// accepted as rare, low-impact cases rather than implemented as a full
/// stack-based matching rewrite.
enum FencedRegionClassifier {
    enum Classification: Equatable {
        case prose
        case frontMatter
        /// The fence's own info string, reduced to its first
        /// whitespace-delimited token and lowercased — a candidate
        /// `LanguageEditingProfileRegistry` key. `nil` for an absent or
        /// empty info string.
        case fencedCode(languageID: String?)
    }

    /// How many lines this scans backward from the caret's own line before
    /// giving up and reporting `.prose` — see §6.12 for why this is a
    /// disclosed, not-unboundedly-correct tradeoff. Measured at ~0.5ms per
    /// 1,000 lines scanned (an independent review's own measurement), so
    /// 5,000 keeps a worst-case per-keystroke classification (this runs on
    /// every keystroke) at a few milliseconds rather than the ~10ms a
    /// 20,000-line cap could reach.
    private static let maximumFenceLinesScanned = 5000

    /// How many lines this scans FORWARD from a document's own first line,
    /// looking for a front-matter block's closing delimiter, before giving
    /// up and reporting "no front matter" — much smaller than the fence
    /// scan's own cap, since a real front-matter block is conventionally a
    /// handful of lines, not proportional to document size.
    private static let maximumFrontMatterLinesScanned = 1000

    static func classify(text: NSString, atUTF16Offset offset: Int) -> Classification {
        let caret = min(max(0, offset), text.length)

        if let frontMatterEnd = frontMatterEnd(in: text), caret < frontMatterEnd {
            return .frontMatter
        }

        var currentLineStart = MarkdownEditingAssistEngine.lineStart(of: caret, in: text)
        var fenceCount = 0
        var nearestLanguageID: String?
        var linesScanned = 0

        // The caret's OWN current line counts too if it is itself a fence
        // delimiter and the caret sits at or past the marker's own end --
        // otherwise a document ending in an unterminated closing fence with
        // no trailing newline (the caret's "own line" IS that closing fence
        // line) would silently drop that closer from the count, since the
        // backward scan below only ever looks at lines STRICTLY BEFORE the
        // caret's line.
        if let fence = fenceDelimiter(lineStart: currentLineStart, in: text),
           caret >= fence.markerEnd {
            fenceCount += 1
            nearestLanguageID = fence.languageID
        }

        while currentLineStart > 0, linesScanned < maximumFenceLinesScanned {
            let previousLineStart = MarkdownEditingAssistEngine.lineStart(of: currentLineStart - 1, in: text)
            if let fence = fenceDelimiter(lineStart: previousLineStart, in: text) {
                fenceCount += 1
                if fenceCount == 1 {
                    nearestLanguageID = fence.languageID
                }
            }
            currentLineStart = previousLineStart
            linesScanned += 1
        }

        guard fenceCount % 2 == 1 else { return .prose }
        return .fencedCode(languageID: nearestLanguageID)
    }

    /// A recognized fence-delimiter line: its marker character, derived
    /// `languageID`, and `markerEnd` (the UTF-16 offset immediately past the
    /// run of backtick/tilde characters, before any info string) -- callers
    /// use `markerEnd` to decide whether a caret sitting ON this very line
    /// has actually crossed past the fence marker itself.
    private struct FenceDelimiter {
        let character: unichar
        let languageID: String?
        let markerEnd: Int
    }

    /// If the line spanning `lineStart..<lineContentEnd` is a fence
    /// delimiter (up to 3 leading spaces, then 3+ of the same backtick or
    /// tilde character), the `FenceDelimiter` it describes.
    private static func fenceDelimiter(
        lineStart: Int,
        in text: NSString
    ) -> FenceDelimiter? {
        var index = lineStart
        var leadingSpaces = 0
        while index < text.length, leadingSpaces < 3,
              MarkdownEditingAssistEngine.character(at: index, in: text) == 0x20 {
            leadingSpaces += 1
            index += 1
        }
        guard index < text.length else { return nil }
        let marker = MarkdownEditingAssistEngine.character(at: index, in: text)
        guard marker == 0x60 || marker == 0x7E else { return nil } // ` or ~
        var fenceLength = 0
        while index < text.length, MarkdownEditingAssistEngine.character(at: index, in: text) == marker {
            fenceLength += 1
            index += 1
        }
        guard fenceLength >= 3 else { return nil }
        let markerEnd = index
        // Plain lines need no forward traversal. Only a real marker run
        // admits the rest of this line for the existing info-string rules.
        let lineContentEnd = MarkdownEditingAssistEngine.lineContentEnd(of: index, in: text)

        let infoString = text.substring(with: NSRange(location: index, length: lineContentEnd - index))
            .trimmingCharacters(in: .whitespaces)
        // A backtick fence's info string cannot contain a backtick: "```x```" is inline code, not a fence.
        if marker == 0x60, infoString.contains("`") {
            return nil
        }
        let firstToken = infoString.split(separator: " ").first.map { String($0).lowercased() }
        return FenceDelimiter(
            character: marker,
            languageID: (firstToken?.isEmpty == false) ? firstToken : nil,
            markerEnd: markerEnd
        )
    }

    /// The UTF-16 offset at which ordinary content resumes after a
    /// front-matter block, or `nil` if `text` doesn't open with one at all.
    private static func frontMatterEnd(in text: NSString) -> Int? {
        guard text.length >= 3, text.character(at: 0) == 0x2D,
              text.character(at: 1) == 0x2D, text.character(at: 2) == 0x2D else { return nil }
        let firstLineContentEnd = MarkdownEditingAssistEngine.lineContentEnd(of: 0, in: text)
        guard isExactly(text, range: NSRange(location: 0, length: firstLineContentEnd), matching: "---") else {
            return nil
        }

        var lineStart = firstLineContentEnd + separatorLength(at: firstLineContentEnd, in: text)
        // Same rule as `MarkdownEngine`: a blank second line makes the opener a thematic break.
        if lineStart < text.length {
            let secondEnd = MarkdownEditingAssistEngine.lineContentEnd(of: lineStart, in: text)
            let second = text.substring(with: NSRange(location: lineStart, length: secondEnd - lineStart))
            if second.trimmingCharacters(in: .whitespaces).isEmpty {
                return nil
            }
        }
        var linesScanned = 0
        while lineStart < text.length, linesScanned < maximumFrontMatterLinesScanned {
            let contentEnd = MarkdownEditingAssistEngine.lineContentEnd(of: lineStart, in: text)
            let lineRange = NSRange(location: lineStart, length: contentEnd - lineStart)
            if isExactly(text, range: lineRange, matching: "---") ||
                isExactly(text, range: lineRange, matching: "...") {
                return contentEnd + separatorLength(at: contentEnd, in: text)
            }
            lineStart = contentEnd + separatorLength(at: contentEnd, in: text)
            linesScanned += 1
        }
        return nil
    }

    private static func isExactly(_ text: NSString, range: NSRange, matching literal: String) -> Bool {
        range.length == literal.utf16.count && text.substring(with: range) == literal
    }

    private static func separatorLength(at contentEnd: Int, in text: NSString) -> Int {
        guard contentEnd < text.length else { return 0 }
        if MarkdownEditingAssistEngine.character(at: contentEnd, in: text) == 0x0D,
           contentEnd + 1 < text.length,
           MarkdownEditingAssistEngine.character(at: contentEnd + 1, in: text) == 0x0A {
            return 2
        }
        return 1
    }
}
