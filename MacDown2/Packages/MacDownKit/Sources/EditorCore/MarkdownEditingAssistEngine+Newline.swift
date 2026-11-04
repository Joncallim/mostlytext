import Foundation

// MARK: - Return / list / task / blockquote continuation

extension MarkdownEditingAssistEngine {
    /// Dispatches on `configuration.isMarkdownFormat` — NOT on
    /// `continuesMarkdownPrefixes` — to Markdown's own list/task/blockquote
    /// continuation, or (EPIC-22 §6.11, Slice 4a) a general "maintain the
    /// previous line's indentation" behavior for every other format.
    ///
    /// An independent hostile review of this slice found dispatching on
    /// `continuesMarkdownPrefixes` alone was a real regression: that flag is
    /// ALSO a genuine, persisted user preference ("Continue lists, quotes,
    /// and indentation on Return") a Markdown user can turn off — and before
    /// this slice, turning it off made Return a pure no-op, full stop. With
    /// only `continuesMarkdownPrefixes` to dispatch on, a Markdown document
    /// with that preference off was indistinguishable from a non-Markdown
    /// document, so it silently fell into the new general behavior and
    /// resurrected indentation-carrying for exactly the users who had
    /// explicitly asked to turn it off. `isMarkdownFormat` is a separate
    /// signal precisely so this method can tell "not Markdown" (run the
    /// general behavior) apart from "Markdown, but the user turned
    /// continuation off" (stay a no-op, matching this flag's own
    /// pre-existing, disclosed contract).
    static func newlineOutcome(
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile
    ) -> EditingAssistOutcome {
        guard selection.length == 0 else { return .passthrough }
        let caret = selection.location

        guard configuration.isMarkdownFormat else {
            return generalNewlineOutcome(caret: caret, text: text, configuration: configuration, profile: profile)
        }
        guard configuration.continuesMarkdownPrefixes else { return .passthrough }
        return markdownNewlineOutcome(caret: caret, text: text, configuration: configuration)
    }

    private static func markdownNewlineOutcome(
        caret: Int,
        text: NSString,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome {
        let prefix = linePrefix(before: caret, in: text)

        let hasConstruct = prefix.listMarker != nil || prefix.taskMarker != nil
            || !prefix.blockquotePrefix.isEmpty
            || !prefix.indentation.isEmpty
        guard hasConstruct else { return .passthrough }

        // Range-scoped emptiness scan on the live source. The content range
        // can span the whole document in a pathological single-line file, so
        // it is never materialized as a Swift `String` copy here.
        let contentEnd = lineContentEnd(of: caret, in: text)
        let contentIsEmpty = text.rangeOfCharacter(
            from: .whitespacesAndNewlines.inverted,
            options: [],
            range: NSRange(
                location: prefix.contentRangeInLine.location,
                length: max(0, contentEnd - prefix.contentRangeInLine.location)
            )
        ).location == NSNotFound

        let separator = lineSeparator(ofLineContaining: caret, in: text)

        if contentIsEmpty {
            return terminationOutcome(prefix: prefix, caret: caret, separator: separator, text: text)
        }
        return continuationOutcome(prefix: prefix, caret: caret, separator: separator, configuration: configuration)
    }

    /// General Return-key indentation, for every non-Markdown format: keeps
    /// the current line's own leading indentation, plus one further level
    /// (via `profile.indentAfterTrailing`, e.g. `{` for C-family languages)
    /// when the character immediately before the caret is one of the
    /// profile's own trailing triggers. A no-op (falls through to native
    /// Return, a bare newline) when there is nothing to add — an unindented
    /// line with no trailing trigger character.
    private static func generalNewlineOutcome(
        caret: Int,
        text: NSString,
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile
    ) -> EditingAssistOutcome {
        let start = lineStart(of: caret, in: text)
        var indentation = parseIndentation(from: start, to: caret, in: text)

        if let previous = scalar(before: caret, in: text), profile.indentAfterTrailing.contains(Character(previous)) {
            let width = profile.defaultIndentWidth ?? configuration.indentationWidth
            indentation += configuration.convertsTabsToSpaces ? String(repeating: " ", count: width) : "\t"
        }
        guard !indentation.isEmpty else { return .passthrough }

        let separator = lineSeparator(ofLineContaining: caret, in: text)
        let replacement = separator + indentation
        return .edit(EditingAssistEdit(
            replacementRange: NSRange(location: caret, length: 0),
            replacementString: replacement,
            resultingSelection: NSRange(location: caret + replacement.utf16.count, length: 0),
            undoActionName: String(localized: "Insert", bundle: .module)
        ))
    }

    /// Empty-construct termination: exit one level. Calculates the entire
    /// result first and performs one replacement — never a delete-then-insert
    /// sequence.
    private static func terminationOutcome(
        prefix: MarkdownLinePrefix,
        caret: Int,
        separator: String,
        text: NSString
    ) -> EditingAssistOutcome {
        let nextLinePrefix: String
        if prefix.listMarker != nil || prefix.taskMarker != nil {
            // Remove the list/task marker; keep quote context.
            nextLinePrefix = prefix.indentation + prefix.blockquotePrefix
        } else if !prefix.blockquotePrefix.isEmpty {
            // Exit the quote entirely.
            nextLinePrefix = prefix.indentation
        } else {
            // Whitespace-only line without a list/quote construct: native.
            return .passthrough
        }
        let lineStart = lineStart(of: caret, in: text)
        let range = NSRange(location: lineStart, length: caret - lineStart)
        let replacementText = separator + nextLinePrefix
        return .edit(EditingAssistEdit(
            replacementRange: range,
            replacementString: replacementText,
            resultingSelection: NSRange(location: lineStart + replacementText.utf16.count, length: 0),
            undoActionName: String(localized: "Continue List", bundle: .module)
        ))
    }

    /// Normal continuation: the separator plus the next line's prefix, inserted at the caret. The replacement starts
    /// with the line separator, so text that already begins with the same separator + prefix is the NEXT line of an
    /// ordinary list/quote — skipping the prefix there (as an earlier version did, to avoid "duplicating" it) made
    /// Return at the end of any non-last item insert a bare blank line and no bullet, which also turns the list
    /// loose in Preview.
    private static func continuationOutcome(
        prefix: MarkdownLinePrefix,
        caret: Int,
        separator: String,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome {
        let replacement = separator + continuationPrefix(for: prefix, configuration: configuration)
        return .edit(EditingAssistEdit(
            replacementRange: NSRange(location: caret, length: 0),
            replacementString: replacement,
            resultingSelection: NSRange(location: caret + replacement.utf16.count, length: 0),
            undoActionName: String(localized: "Continue List", bundle: .module)
        ))
    }

    private static func continuationPrefix(
        for prefix: MarkdownLinePrefix,
        configuration: EditingAssistConfiguration
    ) -> String {
        let outer = prefix.indentation + prefix.blockquotePrefix
        if let marker = prefix.listMarker {
            let markerText: String
            switch marker {
            case let .unordered(character):
                markerText = String(character) + " "
            case let .ordered(rawDigits):
                let digits = configuration.autoIncrementOrderedLists ? incrementedDigits(rawDigits) : rawDigits
                markerText = digits + ". "
            }
            if prefix.taskMarker != nil {
                return outer + markerText + "[ ] "
            }
            return outer + markerText
        }
        if prefix.taskMarker != nil {
            return outer + "[ ] "
        }
        if !prefix.blockquotePrefix.isEmpty {
            return outer
        }
        return prefix.indentation
    }

    /// Safe ordered-number increment: preserves zero-padding width where
    /// possible, repeats the exact digits on overflow/unparseable input.
    private static func incrementedDigits(_ rawDigits: String) -> String {
        guard let value = Int(rawDigits), value < Int.max else { return rawDigits }
        let incremented = String(value + 1)
        if rawDigits.count > incremented.count {
            return String(repeating: "0", count: rawDigits.count - incremented.count) + incremented
        }
        return incremented
    }

    // MARK: - Line prefix parsing

    /// Parses `[indentation][> markers][list marker][task marker]` before the
    /// caret. All offsets are UTF-16.
    static func linePrefix(before caret: Int, in text: NSString) -> MarkdownLinePrefix {
        let start = lineStart(of: caret, in: text)
        let indentation = parseIndentation(from: start, to: caret, in: text)
        var index = start + indentation.utf16.count
        let quote = parseBlockquote(from: &index, to: caret, in: text)
        let listMarker = parseListMarker(from: &index, to: caret, in: text)
        let taskMarker = parseTaskMarker(from: &index, to: caret, in: text)

        return MarkdownLinePrefix(
            indentation: indentation,
            blockquotePrefix: quote,
            listMarker: listMarker,
            taskMarker: taskMarker,
            contentRangeInLine: NSRange(location: index, length: max(0, caret - index))
        )
    }

    private static func parseIndentation(from start: Int, to caret: Int, in text: NSString) -> String {
        var index = start
        while index < caret {
            let character = character(at: index, in: text)
            guard character == 0x20 || character == 0x09 else { break }
            index += 1
        }
        return text.substring(with: NSRange(location: start, length: index - start))
    }

    /// Blockquote markers, preserving each marker's optional space.
    private static func parseBlockquote(from index: inout Int, to caret: Int, in text: NSString) -> String {
        var quote = ""
        while index < caret, character(at: index, in: text) == 0x3E {
            quote.append(">")
            index += 1
            if index < caret, character(at: index, in: text) == 0x20 {
                quote.append(" ")
                index += 1
            }
        }
        return quote
    }

    private static func parseListMarker(from index: inout Int, to caret: Int, in text: NSString) -> ListMarker? {
        guard index < caret else { return nil }
        let marker = character(at: index, in: text)
        if marker == 0x2D || marker == 0x2B || marker == 0x2A {
            if index + 1 < caret, isHorizontalWhitespace(character(at: index + 1, in: text)),
               let scalar = UnicodeScalar(marker)
            // swiftlint:disable:next opening_brace
            {
                index += 2
                return .unordered(Character(scalar))
            }
            return nil
        }
        if !isDigit(marker) {
            return nil
        }
        var digitsEnd = index
        while digitsEnd < caret, isDigit(character(at: digitsEnd, in: text)) {
            digitsEnd += 1
        }
        guard digitsEnd < caret,
              character(at: digitsEnd, in: text) == 0x2E,
              digitsEnd + 1 < caret,
              isHorizontalWhitespace(character(at: digitsEnd + 1, in: text))
        else {
            return nil
        }
        let rawDigits = text.substring(with: NSRange(location: index, length: digitsEnd - index))
        index = digitsEnd + 2
        return .ordered(rawDigits: rawDigits)
    }

    private static func parseTaskMarker(from index: inout Int, to caret: Int, in text: NSString) -> TaskMarker? {
        guard index + 3 < caret, character(at: index, in: text) == 0x5B else { return nil }
        let inner = character(at: index + 1, in: text)
        guard character(at: index + 2, in: text) == 0x5D,
              inner == 0x20 || inner == 0x78 || inner == 0x58,
              isHorizontalWhitespace(character(at: index + 3, in: text))
        else {
            return nil
        }
        index += 4
        return inner == 0x20 ? .unchecked : .checked
    }
}
