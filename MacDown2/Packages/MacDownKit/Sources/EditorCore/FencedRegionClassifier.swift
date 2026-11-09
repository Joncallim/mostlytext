import Foundation

// MARK: - Fenced-code/front-matter classification (EPIC-22 §2.3, §6.12, §7.3, Slice 4b)

/// Bounded, local, synchronous classifier for whether a UTF-16 offset sits
/// inside a fenced code block, YAML front matter, or ordinary prose. Never
/// touches `MarkdownEngine`/`SourceMap` (E10's own "no full parse on the hot
/// path" rule, §2.1) — this is a plain `NSString` scan, closing the E10
/// inherited-debt item §2.3 named.
///
/// The scan returns `.unresolved` when it cannot reach the known document
/// start within its line cap. Callers then suppress Markdown-only assists;
/// guessing `.prose` could mutate source inside a distant open fence. Within
/// the bounded window, closing lines must match the opener's marker and have
/// at least its length. This remains a practical local classifier rather
/// than a second CommonMark parser: container-prefixed fences and indentation
/// beyond three spaces retain their separately documented limitations.
enum FencedRegionClassifier {
    enum Classification: Equatable {
        case prose
        case frontMatter
        /// The bounded scan did not reach a known outside-fence anchor.
        case unresolved
        /// The fence's own info string, reduced to its first
        /// whitespace-delimited token and lowercased — a candidate
        /// `LanguageEditingProfileRegistry` key. `nil` for an absent or
        /// empty info string.
        case fencedCode(languageID: String?)
    }

    /// How many lines this scans backward from the caret's own line before
    /// giving up and reporting `.unresolved`. Measured at ~0.5ms per
    /// 1,000 lines scanned (an independent review's own measurement), so
    /// 5,000 keeps a worst-case per-keystroke classification (this runs on
    /// every keystroke) at a few milliseconds rather than the ~10ms a
    /// 20,000-line cap could reach.
    private static let maximumFenceLinesScanned = 5000

    /// How many lines this scans FORWARD from a document's own first line,
    /// looking for a front-matter block's closing delimiter. Beyond the cap,
    /// the opener remains unresolved so Markdown assists cannot touch YAML.
    private static let maximumFrontMatterLinesScanned = 1000

    private enum FrontMatterBoundary {
        case absent
        case closed(end: Int)
        case unresolved
    }

    static func classify(text: NSString, atUTF16Offset offset: Int) -> Classification {
        let caret = min(max(0, offset), text.length)
        let prefix = frontMatterDecision(in: text, caret: caret)
        if let terminal = prefix.terminal {
            return terminal
        }
        let fenceAnchor = prefix.anchor

        var currentLineStart = MarkdownEditingAssistEngine.lineStart(of: caret, in: text)
        var delimiters: [FenceDelimiter] = []
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
            delimiters.append(fence)
        }

        while currentLineStart > fenceAnchor, linesScanned < maximumFenceLinesScanned {
            let previousLineStart = MarkdownEditingAssistEngine.lineStart(of: currentLineStart - 1, in: text)
            if previousLineStart < fenceAnchor {
                currentLineStart = fenceAnchor
                break
            }
            if let fence = fenceDelimiter(lineStart: previousLineStart, in: text) {
                delimiters.append(fence)
            }
            currentLineStart = previousLineStart
            linesScanned += 1
        }

        guard currentLineStart == fenceAnchor else { return .unresolved }

        // The document's start or the end of closed front matter is a known
        // outside-fence anchor. Never replay YAML's fence-looking lines.
        var active: FenceDelimiter?
        for fence in delimiters.reversed() {
            if let opener = active {
                if fence.canClose, fence.character == opener.character,
                   fence.markerLength >= opener.markerLength {
                    active = nil
                }
            } else {
                active = fence
            }
        }
        return active.map { .fencedCode(languageID: $0.languageID) } ?? .prose
    }

    private static func frontMatterDecision(
        in text: NSString, caret: Int
    ) -> (anchor: Int, terminal: Classification?) {
        switch frontMatterBoundary(in: text) {
        case .absent:
            return (0, nil)
        case let .closed(end):
            if caret < end {
                return (0, .frontMatter)
            }
            if end == text.length {
                return (0, .prose)
            }
            return (end, nil)
        case .unresolved:
            return (0, .unresolved)
        }
    }

    /// A recognized fence-delimiter line: its marker character, derived
    /// `languageID`, and `markerEnd` (the UTF-16 offset immediately past the
    /// run of backtick/tilde characters, before any info string) -- callers
    /// use `markerEnd` to decide whether a caret sitting ON this very line
    /// has actually crossed past the fence marker itself.
    private struct FenceDelimiter {
        let character: unichar
        let markerLength: Int
        let canClose: Bool
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
            markerLength: fenceLength,
            canClose: infoString.isEmpty,
            languageID: (firstToken?.isEmpty == false) ? firstToken : nil,
            markerEnd: markerEnd
        )
    }

    /// Locate a closed block or preserve ambiguity after a plausible opener.
    /// A blank second line still makes the opener a thematic break.
    private static func frontMatterBoundary(in text: NSString) -> FrontMatterBoundary {
        guard text.length >= 3,
              text.character(at: 0) == 0x2D || text.character(at: 0) == 0xFEFF else { return .absent }
        let firstLineContentEnd = MarkdownEditingAssistEngine.lineContentEnd(of: 0, in: text)
        guard isFrontMatterDelimiter(
            text, range: NSRange(location: 0, length: firstLineContentEnd),
            matching: "---", allowLeadingBOM: true
        ) else {
            return .absent
        }

        var lineStart = firstLineContentEnd + separatorLength(at: firstLineContentEnd, in: text)
        // Same rule as `MarkdownEngine`: a blank second line makes the opener a thematic break.
        if lineStart <= text.length {
            let secondEnd = MarkdownEditingAssistEngine.lineContentEnd(of: lineStart, in: text)
            let second = text.substring(with: NSRange(location: lineStart, length: secondEnd - lineStart))
            if second.trimmingCharacters(in: .whitespaces).isEmpty {
                return .absent
            }
        }
        var linesScanned = 0
        while lineStart < text.length, linesScanned < maximumFrontMatterLinesScanned {
            let contentEnd = MarkdownEditingAssistEngine.lineContentEnd(of: lineStart, in: text)
            let lineRange = NSRange(location: lineStart, length: contentEnd - lineStart)
            if isFrontMatterDelimiter(text, range: lineRange, matching: "---") ||
                isFrontMatterDelimiter(text, range: lineRange, matching: "...") {
                return .closed(end: contentEnd + separatorLength(at: contentEnd, in: text))
            }
            lineStart = contentEnd + separatorLength(at: contentEnd, in: text)
            linesScanned += 1
        }
        return .unresolved
    }

    /// Match `MarkdownEngine.FrontMatterExtractor`'s delimiter spelling without importing
    /// the parser into this per-keystroke editor module. It permits one BOM on the first
    /// line and trailing whitespace, but never indentation or extra visible characters.
    private static func isFrontMatterDelimiter(
        _ text: NSString,
        range: NSRange,
        matching literal: String,
        allowLeadingBOM: Bool = false
    ) -> Bool {
        var markerStart = range.location
        let end = NSMaxRange(range)
        if allowLeadingBOM, markerStart < end, text.character(at: markerStart) == 0xFEFF {
            markerStart += 1
        }
        let marker = literal.utf16
        guard markerStart + marker.count <= end else { return false }
        for (offset, unit) in marker.enumerated() where text.character(at: markerStart + offset) != unit {
            return false
        }
        let trailingStart = markerStart + marker.count
        let trailing = NSRange(location: trailingStart, length: end - trailingStart)
        return text.rangeOfCharacter(from: .whitespaces.inverted, range: trailing).location == NSNotFound
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
