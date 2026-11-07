import Foundation

/// Maintains UTF-16 logical line-start offsets for one document's live text.
///
/// A "logical line" is a source line as delimited by LF, CRLF, or a bare CR
/// (classic Mac OS 9 line endings) — never a wrapped visual line. Powers the
/// gutter, status bar, Go to Line/Column, and logical-line commands
/// (Duplicate/Move/Sort/Join/Trim).
///
/// Unlike `MarkdownEngine.SourceMap` (which this type's line/column
/// convention otherwise matches: UTF-16 internally, character counts for
/// user-facing display), `EditorLineIndex` treats a bare `\r` as a line
/// terminator in its own right — E22's Go to Line/Column acceptance
/// criterion is "correct for LF/CRLF/CR," and `SourceMap` only truly
/// distinguishes LF/CRLF (a lone `\r` never starts a new line under its
/// `\n`-only scan). `SourceMap` is Markdown-parse-debounced and rebuilt
/// wholesale on every reparse; `EditorLineIndex` is edited incrementally on
/// every keystroke and must never rescan more than the affected span.
public struct EditorLineIndex: Sendable, Equatable {
    /// UTF-16 offset at which each 1-based logical line starts.
    /// `lineStartOffsets[0]` is line 1 and is always 0. Count == lineCount.
    public private(set) var lineStartOffsets: [Int]

    /// Total UTF-16 length of the indexed text.
    public private(set) var utf16Length: Int

    public var lineCount: Int {
        lineStartOffsets.count
    }

    public init(text: NSString) {
        (lineStartOffsets, utf16Length) = Self.scan(text, from: 0, to: text.length, firstLineStart: 0)
    }

    /// Full rebuild — only for whole-document replacement/reload (mirrors
    /// `applyDocumentReplacement`'s "whole document changed" case). Every
    /// other edit must go through `applying(editedRange:replacementUTF16Length:newText:)`.
    public mutating func rebuild(text: NSString) {
        self = EditorLineIndex(text: text)
    }

    /// Incremental update from one edit: `editedRange` is the UTF-16 range
    /// that was replaced, expressed in the *previous* text's coordinates;
    /// `replacementUTF16Length` is the UTF-16 length of what replaced it;
    /// `newText` is the full text after the edit.
    ///
    /// Only rescans the line(s) touching the edit, plus one full untouched
    /// line of margin on EACH side, so a terminator that would otherwise
    /// straddle the rescan boundary is always resolved entirely inside the
    /// rescanned span, never split across it. The trailing margin handles
    /// e.g. an edit inserting a trailing `\r` immediately before old content
    /// beginning with `\n`, which only becomes a real CRLF pair after the
    /// edit. The LEADING margin exists for the mirror case: an edit whose
    /// `location` sits exactly at the start of a line preceded by a lone-CR
    /// terminator, where new content beginning with `\n` would combine with
    /// that untouched preceding CR into a new CRLF — a rescan starting
    /// exactly at the edit would never re-examine that preceding CR at all.
    /// Every line beyond both margins is O(1) shifted by the edit's length
    /// delta, never rescanned.
    public mutating func applying(editedRange: NSRange, replacementUTF16Length: Int, newText: NSString) {
        let delta = replacementUTF16Length - editedRange.length
        let oldEditEnd = editedRange.location + editedRange.length

        let startLine = line(atUTF16Offset: editedRange.location)
        let touchedEndLine = oldEditEnd >= utf16Length ? lineCount : line(atUTF16Offset: oldEditEnd)
        // One extra untouched line of margin on each side (see doc comment above).
        let rescanStartLine = max(1, startLine - 1)
        let marginEndLine = min(lineCount, touchedEndLine + 1)

        let prefixCount = rescanStartLine - 1 // lines 1...prefixCount are strictly before the edit; unaffected.
        var offsets = Array(lineStartOffsets[0 ..< prefixCount])

        let rescanStart = lineStartOffsets[rescanStartLine - 1]
        let hasOldTail = marginEndLine < lineCount
        let oldTailStart = hasOldTail ? lineStartOffsets[marginEndLine] : utf16Length
        let rescanEnd = oldTailStart + delta

        var (rescanned, _) = Self.scan(
            newText,
            from: rescanStart,
            to: max(rescanStart, rescanEnd),
            firstLineStart: rescanStart
        )
        // The margin guarantees the terminator ending the line just before
        // `oldTailStart` lies entirely inside the rescanned window, so the
        // scan legitimately (and necessarily) finds it and reports a line
        // start at exactly `rescanEnd` — but that is the exact same offset
        // (shifted by `delta`) the tail copy below is about to supply as
        // its own first element. Drop the rescan's copy so the two do not
        // both contribute the same line start.
        if hasOldTail, rescanned.last == rescanEnd {
            rescanned.removeLast()
        }
        // The complete output count is known; avoid repeated capacity growth while copying a large tail.
        let tailCount = hasOldTail ? lineStartOffsets.count - marginEndLine : 0
        offsets.reserveCapacity(prefixCount + rescanned.count + tailCount)
        offsets.append(contentsOf: rescanned)

        if hasOldTail {
            for oldOffset in lineStartOffsets[marginEndLine...] {
                offsets.append(oldOffset + delta)
            }
        }

        lineStartOffsets = offsets
        utf16Length += delta
    }

    /// 1-based line containing the given UTF-16 offset (binary search,
    /// matching `SourceMap.line(atUTF16Offset:)`'s convention: offsets past
    /// the end clamp to the last line, negative offsets clamp to line 1).
    public func line(atUTF16Offset offset: Int) -> Int {
        guard offset >= 0 else { return 1 }
        guard offset < utf16Length else { return lineCount }
        var low = 0
        var high = lineStartOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    /// UTF-16 range of one logical line's content, excluding its terminator
    /// (unlike `SourceMap.utf16Range(ofLines:)`, which deliberately keeps a
    /// lone `\r` as line content and only excludes a final `\n` — see this
    /// type's header comment). Needs `text` to measure the terminator's
    /// actual width (1 unit for LF/CR, 2 for CRLF), since `EditorLineIndex`
    /// stores only offsets.
    public func utf16Range(ofLine line: Int, in text: NSString) -> NSRange {
        guard line >= 1, line <= lineCount else { return NSRange(location: utf16Length, length: 0) }
        let start = lineStartOffsets[line - 1]
        guard line < lineCount else {
            return NSRange(location: start, length: max(0, utf16Length - start))
        }
        let nextLineStart = lineStartOffsets[line]
        let terminatorWidth = Self.terminatorWidth(endingAt: nextLineStart, in: text)
        return NSRange(location: start, length: max(0, nextLineStart - start - terminatorWidth))
    }

    /// The width, in UTF-16 units, of the line terminator immediately
    /// preceding `nextLineStart` (which is, by construction, always
    /// immediately after some terminator — every `lineStartOffsets` entry
    /// past the first is one). 2 for a CRLF pair, else 1.
    private static func terminatorWidth(endingAt nextLineStart: Int, in text: NSString) -> Int {
        guard nextLineStart >= 2 else { return min(1, nextLineStart) }
        let previous = text.character(at: nextLineStart - 1)
        if previous == 0x0A, text.character(at: nextLineStart - 2) == 0x0D {
            return 2
        }
        return 1
    }

    /// 1-based character (not UTF-16 unit) column for user-facing display —
    /// counts extended grapheme clusters between the line start and
    /// `offset`, so CJK/emoji/combining sequences count as MacDown 2's other
    /// user-facing text positions already do.
    public func column(atUTF16Offset offset: Int, onLine lineNumber: Int, in text: NSString) -> Int {
        let lineStart = lineNumber >= 1 && lineNumber <= lineCount ? lineStartOffsets[lineNumber - 1] : 0
        let clampedOffset = max(lineStart, min(offset, utf16Length))
        guard clampedOffset > lineStart else { return 1 }
        let range = NSRange(location: lineStart, length: clampedOffset - lineStart)
        let substring = text.substring(with: range)
        return substring.count + 1
    }

    /// UTF-16 offset for a 1-based (line, column) pair — the inverse of
    /// `column(atUTF16Offset:onLine:in:)`. `column` is a 1-based character
    /// (grapheme-cluster) count, matching that method's convention: column 1
    /// is the line's own start. Powers Go to Line/Column.
    ///
    /// Out-of-range `line` clamps to `1...lineCount`; out-of-range `column`
    /// (below 1, or beyond the line's actual length) clamps to the line's
    /// start or end respectively — it never advances into or past the line's
    /// terminator, matching this type's clamping convention throughout.
    public func utf16Offset(forLine line: Int, column: Int, in text: NSString) -> Int {
        let clampedLine = min(max(1, line), lineCount)
        let lineStart = lineStartOffsets[clampedLine - 1]
        guard column > 1 else { return lineStart }

        let lineContent = text.substring(with: utf16Range(ofLine: clampedLine, in: text))
        var remaining = column - 1
        var utf16Advance = 0
        for character in lineContent {
            guard remaining > 0 else { break }
            utf16Advance += character.utf16.count
            remaining -= 1
        }
        return lineStart + utf16Advance
    }

    /// Scans `[start, end)` of `text` for LF/CRLF/CR line starts, returning
    /// them (including `firstLineStart` itself) plus the scanned length.
    /// Used by both the full-document `init` (`start == 0`) and the
    /// incremental rescan window.
    private static func scan(_ text: NSString, from start: Int, to end: Int, firstLineStart: Int) -> ([Int], Int) {
        var offsets = [firstLineStart]
        var index = start
        while index < end {
            let unit = text.character(at: index)
            if unit == 0x0A { // \n
                offsets.append(index + 1)
            } else if unit == 0x0D { // \r
                if index + 1 < text.length, text.character(at: index + 1) == 0x0A {
                    offsets.append(index + 2)
                    index += 1
                } else {
                    offsets.append(index + 1)
                }
            }
            index += 1
        }
        return (offsets, end - start)
    }
}
