import Foundation

/// Scans raw source text for math spans, using literally the same matching
/// rule as `Textual`'s sealed `.math` `SyntaxExtension`
/// (`PatternTokenizer.Pattern.mathBlock`/`.mathInline`, verified against the
/// checked-out `textual@0.5.0` source — epic-19-implementation.md §2.1, §6.1)
/// so Preview's pre-processing and Export's `MathContribution` can never
/// disagree with each other, or with what Textual itself will actually
/// render, about where an equation starts and ends.
///
/// `Textual`'s own `PatternTokenizer` cannot be reused directly — its types
/// are not `public` (epic-19-implementation.md §2.1) — so this is an
/// independent implementation of the identical rule: a left-to-right scan
/// that, at each position, tries the display pattern first and the inline
/// pattern second, each as a PREFIX match (not a search) at that exact
/// position; a position where neither matches advances by one character as
/// literal text. This ordering is what stops a `$$...$$` block from being
/// seen as two adjacent, incorrectly-matched inline spans.
///
/// The two regex literals below are copied verbatim from
/// `Textual/Internal/MarkdownParser/PatternTokenizer.swift`'s
/// `.mathBlock`/`.mathInline` patterns. If a future `textual` upgrade
/// changes them, `MathSpanScannerTests`'s fixture corpus is what catches the
/// drift — do not let this comment substitute for re-checking the dependency
/// source at that time.
public enum MathSpanScanner {
    /// **Deliberate, documented divergence from Textual's own tokenizer**
    /// (adversarial-review finding, post-merge, `chatgpt-codex-connector`):
    /// for input like `Price: \$5 and $x=1$ today.`, Textual's real
    /// tokenizer (and this scanner, before this fix) reaches the escaped
    /// `\$` one character at a time — the backslash matches neither
    /// pattern, so it is skipped as plain text, and the scan resumes
    /// exactly AT the following `$` with no memory that it was just
    /// escaped, so `mathInline` matches "$5 and $" as a phantom equation,
    /// consuming the real `$x=1$` equation's opening delimiter and leaving
    /// `x=1$` behind as broken literal text.
    ///
    /// This scanner now skips an escaped `\$` as a two-character unit when
    /// no pattern matches at the current position, so the `$` immediately
    /// after `\` is never revisited as a fresh opening delimiter. Textual's
    /// own sealed tokenizer has no equivalent fix and cannot be patched
    /// from here, so Export (which uses this scanner directly) now handles
    /// this input correctly while Preview (whose actual glyph rendering
    /// depends on Textual's own real tokenizer, not merely on what this
    /// scanner privately concludes) still inherits Textual's original
    /// behavior — a residual, Preview-only limitation recorded in
    /// epic-19-implementation.md §18, accepted because Export can be fully
    /// correct on its own and Preview cannot be fixed without fragile,
    /// speculative rewriting of prose this epic does not otherwise touch.
    public static func scan(_ text: String) -> [MathSpan] {
        // Scanned over UTF-16 units, not `Character`s: a `$` glued to a grapheme-extending scalar (ZWNJ after Latin
        // text in Persian, ZWJ, VS16, combining marks) belongs to a different `Character`, so the closing delimiter
        // of `$x$‌ها` was never seen and the span swallowed the prose. The matching rules are the two patterns
        // documented below, hand-written so the scan stays linear.
        let units = Array(text.utf16)
        var spans: [MathSpan] = []
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == backslash, index + 1 < units.count, units[index + 1] == dollar {
                index += 2 // an escaped `\$` is never the start of a span
                continue
            }
            guard unit == dollar else {
                index += 1
                continue
            }
            if let end = displayEnd(from: index, in: units) {
                spans.append(makeSpan(units, index ..< end, delimiter: 2, style: .display))
                index = end
            } else if let end = inlineEnd(from: index, in: units) {
                spans.append(makeSpan(units, index ..< end, delimiter: 1, style: .inline))
                index = end
            } else {
                index += 1
            }
        }
        return spans
    }

    private static let dollar: UInt16 = 0x24
    private static let backslash: UInt16 = 0x5C
    private static let lineFeed: UInt16 = 0x0A
    private static let carriageReturn: UInt16 = 0x0D

    private static func makeSpan(
        _ units: [UInt16],
        _ range: Range<Int>,
        delimiter: Int,
        style: MathSpan.Style
    ) -> MathSpan {
        let latex = String(decoding: units[(range.lowerBound + delimiter) ..< (range.upperBound - delimiter)],
                           as: UTF16.self)
        return MathSpan(range: range, style: style, latex: latex)
    }

    /// Length of the line terminator at `index` (CRLF is one terminator), or 0.
    private static func terminatorLength(at index: Int, in units: [UInt16]) -> Int {
        guard index < units.count else { return 0 }
        if units[index] == lineFeed {
            return 1
        }
        guard units[index] == carriageReturn else { return 0 }
        return index + 1 < units.count && units[index + 1] == lineFeed ? 2 : 1
    }

    /// Whether a blank line (terminator, optional spaces/tabs, terminator) starts at `index`.
    private static func blankLineStarts(at index: Int, in units: [UInt16]) -> Bool {
        let first = terminatorLength(at: index, in: units)
        guard first > 0 else { return false }
        var cursor = index + first
        while cursor < units.count, units[cursor] == 0x20 || units[cursor] == 0x09 {
            cursor += 1
        }
        return terminatorLength(at: cursor, in: units) > 0
    }

    /// `$$ … $$` with at least one content unit, the nearest closing `$$`, and no blank line in between — Textual's
    /// `mathBlock` (`(?s)\$\$(.+?)\$\$`) plus the blank-line rule. Returns the end offset, or `nil`.
    private static func displayEnd(from start: Int, in units: [UInt16]) -> Int? {
        guard start + 1 < units.count, units[start + 1] == dollar else { return nil }
        let contentStart = start + 2
        var checked = contentStart // every position below this has been checked for a blank line
        var closing = contentStart + 1
        while closing + 1 < units.count {
            while checked < closing {
                if blankLineStarts(at: checked, in: units) {
                    return nil
                }
                checked += 1
            }
            if units[closing] == dollar, units[closing + 1] == dollar {
                return closing + 2
            }
            closing += 1
        }
        return nil
    }

    /// `$ … $` — Textual's `mathInline` (`\$(?!\$)((?:\\\$|[^$\n\r])+)\$`, with `\r` also excluded): one or more
    /// units that are an escaped `\$` pair or anything but `$`/newline, then a closing `$`. When the greedy scan runs
    /// into a newline or the end, the regex backtracks to the last `\$` pair and lets its `$` close the span.
    private static func inlineEnd(from start: Int, in units: [UInt16]) -> Int? {
        guard start + 1 < units.count, units[start + 1] != dollar else { return nil }
        var cursor = start + 1
        var lastEscape: Int?
        while cursor < units.count {
            let unit = units[cursor]
            if unit == dollar {
                return cursor + 1
            }
            if unit == lineFeed || unit == carriageReturn {
                break
            }
            if unit == backslash, cursor + 1 < units.count, units[cursor + 1] == dollar {
                lastEscape = cursor
                cursor += 2
            } else {
                cursor += 1
            }
        }
        return lastEscape.map { $0 + 2 }
    }
}
