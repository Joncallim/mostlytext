import AppKit
import FileCore

/// Pure planning for "insert this snippet at every caret" — the whole
/// multi-caret behavior lives here so it is testable without a text view.
/// Each selection is replaced by its own expansion (its own `${selection}`,
/// its own indentation, its own line's terminator) and leaves one caret at
/// its own final-caret position (EPIC-22 journey J7).
enum EditorSnippetInsertion {
    static let undoActionName = String(localized: "Insert Snippet", bundle: .module)

    static func transaction(
        template: SnippetTemplate,
        text: NSString,
        selection: EditorSelectionSet,
        clipboard: String?,
        defaultLineEnding: LineEnding
    ) -> EditorEditTransaction? {
        guard selection.ranges.allSatisfy({ NSMaxRange($0) <= text.length }) else { return nil }
        var replacements: [TextReplacement] = []
        var carets: [NSRange] = []
        var delta = 0
        for range in selection.ranges {
            let ending = lineEnding(near: range.location, in: text, fallback: defaultLineEnding)
            let expansion = template.expand(
                selection: text.substring(with: range),
                clipboard: clipboard.map { adaptingLineBreaks(in: $0, to: ending) },
                indent: indent(before: range.location, in: text),
                lineEnding: ending
            )
            replacements.append(TextReplacement(range: range, replacementText: expansion.text))
            carets.append(NSRange(location: range.location + delta + expansion.caretOffset, length: 0))
            delta += expansion.text.utf16.count - range.length
        }
        return EditorEditTransaction(
            replacements: replacements,
            undoActionName: undoActionName,
            resultingSelection: EditorSelectionSet(ranges: carets, primaryIndex: selection.primaryIndex)
        )
    }

    /// The leading blanks of `location`'s line, up to `location` — what a
    /// continuation line of the snippet must repeat to stay aligned.
    static func indent(before location: Int, in text: NSString) -> String {
        let lineStart = text.lineRange(for: NSRange(location: location, length: 0)).location
        var end = lineStart
        while end < location, isBlank(text.character(at: end)) {
            end += 1
        }
        return text.substring(with: NSRange(location: lineStart, length: end - lineStart))
    }

    /// The terminator the document already uses at `location`'s line, else the
    /// previous line's, else `fallback` — never invents a second convention in
    /// a document that already has one (invariant #5).
    /// Clipboard text comes from outside the document, so its line breaks follow
    /// the insertion point's own line ending; the selection is the document's
    /// own text and stays verbatim (invariant #5).
    static func adaptingLineBreaks(in text: String, to ending: String) -> String {
        // utf8 scan: `String.contains("\n")` is false for a "\r\n" grapheme.
        guard text.utf8.contains(where: { $0 == 0x0A || $0 == 0x0D }) else { return text }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n", options: .literal)
            .replacingOccurrences(of: "\r", with: "\n", options: .literal)
            .replacingOccurrences(of: "\n", with: ending, options: .literal)
    }

    static func lineEnding(near location: Int, in text: NSString, fallback: LineEnding) -> String {
        let probe = NSRange(location: location, length: 0)
        if let own = terminator(of: probe, in: text) {
            return own
        }
        let lineStart = text.lineRange(for: probe).location
        if lineStart > 0, let previous = terminator(of: NSRange(location: lineStart - 1, length: 0), in: text) {
            return previous
        }
        return fallback.text
    }

    private static func terminator(of range: NSRange, in text: NSString) -> String? {
        var lineEnd = 0
        var contentsEnd = 0
        text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: range)
        let terminator = text.substring(with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd))
        return ["\n", "\r\n", "\r"].contains(terminator) ? terminator : nil
    }

    private static func isBlank(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09
    }
}

public extension EditorTextSystem {
    /// Expands `template` at every selection, as one undoable edit. Returns
    /// `false` (changing nothing) while an IME composition is active — marked
    /// text is never rewritten (invariant #9) — or while an editing assist or
    /// programmatic update is in flight, or when the view is read-only.
    @discardableResult
    func insertSnippet(
        _ template: SnippetTemplate,
        clipboard: String?,
        defaultLineEnding: LineEnding = .lineFeed
    ) -> Bool {
        guard textView.isEditable, !textView.hasMarkedText() else { return false }
        guard !isPerformingEditingAssist, !isPerformingProgrammaticTextUpdate else { return false }
        guard let text = assistTextSource,
              let transaction = EditorSnippetInsertion.transaction(
                  template: template,
                  text: text,
                  selection: selectionSet,
                  clipboard: clipboard,
                  defaultLineEnding: defaultLineEnding
              )
        else { return false }
        apply(transaction)
        return true
    }
}
