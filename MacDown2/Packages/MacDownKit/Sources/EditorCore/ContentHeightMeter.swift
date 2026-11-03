import AppKit

/// Measures the height a document needs when wrapped to a width, paragraph by paragraph.
///
/// `NSString.boundingRect` over the WHOLE document is quadratic for non-Latin or mixed-script
/// text (Release builds: 250 lines of Japanese+emoji 2 s, 1000 lines 35 s) and it ran on the
/// main thread 50 ms after every edit. Paragraphs stack, so the document height is the sum of
/// its paragraphs' heights (an empty paragraph is one line) — the same number, measured in
/// linear time, and cached per paragraph so an edit re-measures only the paragraph it touched.
@MainActor
final class ContentHeightMeter {
    private var cacheKey = ""
    private var heights: [Int: CGFloat] = [:]
    private static let maximumCachedParagraphs = 250_000
    /// UTF-16 units above which the whole document is estimated rather than measured.
    static let estimationThreshold = 1_000_000
    static let maximumMeasuredParagraphLength = 20000

    func height(of string: NSString, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let key = Self.cacheKey(width: width, attributes: attributes)
        if key != cacheKey || heights.count > Self.maximumCachedParagraphs {
            cacheKey = key
            heights.removeAll(keepingCapacity: true)
        }
        let size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        func measure(_ paragraph: NSString) -> CGFloat {
            paragraph.boundingRect(
                with: size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            ).height
        }

        let estimator = LineHeightEstimator(width: width, attributes: attributes)
        let estimatesEverything = string.length > Self.estimationThreshold
        var total: CGFloat = 0
        Self.forEachParagraph(in: string) { range in
            // Measuring is O(document) after every edit pause and quadratic inside one long CJK/emoji paragraph, so
            // a huge document, or a huge paragraph, is sized from its length instead (a 10 MB file stalled the main
            // thread for ~0.7 s per pause; one 400k-character CJK paragraph for ~24 s).
            if estimatesEverything || range.length > Self.maximumMeasuredParagraphLength {
                total += estimator.height(of: string, range: range)
                return
            }
            let paragraph = string.substring(with: range)
            let hash = paragraph.hashValue
            if let cached = heights[hash] {
                total += cached
                return
            }
            let measured = measure(paragraph as NSString)
            heights[hash] = measured
            total += measured
        }
        return total
    }

    /// Calls `body` with each paragraph's range (terminator excluded), INCLUDING empty ones and
    /// the empty paragraph after a trailing terminator. A paragraph ends at `\n`, `\r`, `\r\n` or
    /// U+2029.
    static func forEachParagraph(in string: NSString, _ body: (NSRange) -> Void) {
        HeightParagraphScanner.forEach(in: string, body)
    }

    private static func cacheKey(width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> String {
        let font = (attributes[.font] as? NSFont).map { "\($0.fontName)-\($0.pointSize)" } ?? "nofont"
        let style = (attributes[.paragraphStyle] as? NSParagraphStyle).map { "\($0)" } ?? "nostyle"
        return "\(width)|\(font)|\(style)"
    }
}

/// A wrap-aware height estimate for text too large to measure. It deliberately OVER-estimates: an estimate that is
/// too short leaves the end of the document unreachable (the frame is shorter than the layout), while one that is too
/// long only adds blank space below the last line.
///
/// The line height is measured from the real attributes, so a paragraph style's `lineHeightMultiple`/spacing counts.
/// Layout is simulated with a greedy word wrap over per-unit advances: ASCII at the font's average advance, everything
/// else (CJK, emoji, surrogate halves) at a full em, a tab at the paragraph's tab interval, and U+2028 / U+0085 /
/// VT / FF as forced line breaks (the meter splits paragraphs only on LF, CR and U+2029). A word longer than a line
/// wraps by characters, as CJK text does.
struct LineHeightEstimator {
    private let lineHeight: CGFloat
    private let availableWidth: CGFloat
    private let asciiAdvance: CGFloat
    private let wideAsciiAdvance: CGFloat
    private let cjkAdvance: CGFloat
    private let symbolAdvance: CGFloat
    private let tabWidth: CGFloat

    init(width: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        var measuring = attributes
        measuring[.font] = font
        lineHeight = ceil(("Ag" as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: measuring
        ).height)
        availableWidth = max(width, 1)
        asciiAdvance = max(("n" as NSString).size(withAttributes: [.font: font]).width, 1)
        // The widest ASCII glyphs (W, m, w, @…) are far wider than "n" in a proportional font; text full of them would
        // otherwise be under-priced. Monospaced fonts make the two equal.
        wideAsciiAdvance = max(("W" as NSString).size(withAttributes: [.font: font]).width, asciiAdvance)
        cjkAdvance = max(font.pointSize, asciiAdvance)
        // Symbols and emoji that fit one UTF-16 unit (⌚ ✅ ❌) are wider than an em; surrogate halves (the rest of
        // emoji) are priced at half of that each, so a pair is the same.
        symbolAdvance = max(font.pointSize * 1.5, cjkAdvance)
        let style = attributes[.paragraphStyle] as? NSParagraphStyle
        let interval = style?.defaultTabInterval ?? 0
        // Real tab stops depend on the font and stop positions; eight columns is a safe upper bound.
        tabWidth = max(interval > 0 ? interval : 28, asciiAdvance * 8)
    }

    private static func isWideASCII(_ unit: unichar) -> Bool {
        (0x41 ... 0x5A).contains(unit) || unit == 0x6D || unit == 0x77 || unit == 0x40 || unit == 0x25 || unit == 0x26
    }

    func height(of string: NSString, range: NSRange) -> CGFloat {
        var lines = 1
        var lineWidth: CGFloat = 0
        var wordWidth: CGFloat = 0

        func flushWord() {
            guard wordWidth > 0 else { return }
            if lineWidth + wordWidth > availableWidth {
                if lineWidth > 0 {
                    lines += 1
                    lineWidth = 0
                }
                let extra = (wordWidth / availableWidth).rounded(.down)
                lines += Int(extra)
                lineWidth = wordWidth - extra * availableWidth
            } else {
                lineWidth += wordWidth
            }
            wordWidth = 0
        }

        var index = range.location
        let end = NSMaxRange(range)
        while index < end {
            let unit = string.character(at: index)
            switch unit {
            case 0x2028, 0x85, 0x0B, 0x0C:
                flushWord()
                lines += 1
                lineWidth = 0
            case 0x20, 0x09:
                flushWord()
                lineWidth += unit == 0x20 ? asciiAdvance : tabWidth
                if lineWidth > availableWidth {
                    lines += 1
                    lineWidth = 0
                }
            case ..<0x80:
                wordWidth += Self.isWideASCII(unit) ? wideAsciiAdvance : asciiAdvance
            case 0xD800 ... 0xDFFF:
                wordWidth += symbolAdvance / 2
            case 0x2E80 ... 0x9FFF, 0xAC00 ... 0xD7AF, 0xF900 ... 0xFAFF, 0xFF00 ... 0xFFEF:
                wordWidth += cjkAdvance
            default:
                wordWidth += symbolAdvance
            }
            index += 1
        }
        flushWord()
        return CGFloat(lines) * lineHeight
    }
}
