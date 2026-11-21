import Foundation

/// Extracts CommonMark link reference definitions from the whole document
/// source, so they can be replayed into each independently-parsed preview
/// block.
///
/// A link reference definition (`[label]: destination "title"`) is resolved
/// during parsing and is normally visible to every reference anywhere in the
/// same document. Because each ``PreviewBlock`` is handed to Textual as its
/// own standalone parse, a definition living in one block is invisible to a
/// `[text][label]` reference living in another — the reference renders as
/// literal text instead of a link. Prepending every definition's original
/// line to a block's source before it reaches Textual gives that block's
/// parse the same reference map a whole-document parse would have had.
/// Reference definitions produce no visible output on their own, so this is
/// safe to do unconditionally.
///
/// Known limitations, accepted as proportionate to the common case:
/// - Only single-line definitions are recognized. CommonMark also allows the
///   destination/title to continue onto a following line; that form is rare
///   in practice and is left to degrade to the pre-existing behavior
///   (unresolved reference rendered as literal text).
/// - Extraction is text-only and not fence-aware, so a line that looks like a
///   definition inside a fenced code block would be misidentified. This
///   mirrors the same trade-off already accepted for reference-definition
///   detection versus a full CommonMark parse.
public enum PreviewLinkDefinitions {
    /// `source` with the definitions it references prepended; see ``PreviewLinkDefinitionIndex``. Callers that
    /// prefix many blocks build the index once instead.
    public static func prefixed(_ source: String, with definitions: [String]) -> String {
        PreviewLinkDefinitionIndex(definitions).prefixed(source)
    }

    /// Reference definition lines found anywhere in `text`, in document
    /// order, with original formatting preserved.
    ///
    /// Recognizes a line matching: up to three leading spaces (CommonMark's
    /// allowance for a definition to be indented like other block content),
    /// `[label]:`, at least one space or tab, then a destination starting
    /// with a non-whitespace character, optionally followed by a title in
    /// quotes or parentheses. Footnote labels (`[^1]:`) and free text after the
    /// destination are not definitions.
    ///
    /// Scans a `unichar` buffer directly rather than matching a `Regex` per
    /// line — ~30x faster on a 1 MB document (19.6 ms → 0.64 ms), verified
    /// against the `Regex` version it replaced across empty labels, missing
    /// separators, the 3-vs-4-space indent boundary, tab/mixed separators,
    /// and non-ASCII whitespace immediately after the colon (which must not
    /// count as the start of a destination).
    public static func extract(from text: String) -> [String] {
        let nsText = text as NSString
        let length = nsText.length
        guard length > 0 else { return [] }

        var buffer = [unichar](repeating: 0, count: length)
        nsText.getCharacters(&buffer, range: NSRange(location: 0, length: length))

        var definitions: [String] = []
        var lineStart = 0
        var index = 0

        while index <= length {
            if index == length || buffer[index] == Self.newline || buffer[index] == Self.carriageReturn {
                if isDefinitionLine(buffer, from: lineStart, to: index) {
                    definitions.append(nsText.substring(with: NSRange(
                        location: lineStart,
                        length: index - lineStart
                    )))
                }
                // Treat CRLF as one break while also admitting CR-only and
                // mixed-break source. The original line bytes stay unchanged.
                if index < length, buffer[index] == Self.carriageReturn,
                   index + 1 < length, buffer[index + 1] == Self.newline {
                    index += 1
                }
                lineStart = index + 1
            }
            index += 1
        }

        return definitions
    }

    private static let space = unichar(0x20)
    private static let tab = unichar(0x09)
    private static let newline = unichar(0x0A)
    private static let carriageReturn = unichar(0x0D)
    private static let openBracket = unichar(0x5B) // [
    private static let closeBracket = unichar(0x5D) // ]
    private static let colon = unichar(0x3A) // :
    private static let caret = unichar(0x5E) // ^
    private static let lessThan = unichar(0x3C) // <
    private static let greaterThan = unichar(0x3E) // >
    private static let doubleQuote = unichar(0x22) // "
    private static let singleQuote = unichar(0x27) // '
    private static let openParen = unichar(0x28) // (
    private static let closeParen = unichar(0x29) // )

    private static func isDefinitionLine(_ buffer: [unichar], from lineStart: Int, to lineEnd: Int) -> Bool {
        var cursor = lineStart

        var spaceCount = 0
        while cursor < lineEnd, buffer[cursor] == space, spaceCount < 3 {
            cursor += 1
            spaceCount += 1
        }

        guard cursor < lineEnd, buffer[cursor] == openBracket else { return false }
        cursor += 1

        // Label: one or more characters that are not ']' (line bounds
        // already exclude '\n').
        let labelStart = cursor
        while cursor < lineEnd, buffer[cursor] != closeBracket {
            cursor += 1
        }
        guard cursor > labelStart, cursor < lineEnd, buffer[cursor] == closeBracket else { return false }
        // `[^1]: text` is a footnote definition, not a link reference definition.
        guard buffer[labelStart] != caret else { return false }
        cursor += 1

        guard cursor < lineEnd, buffer[cursor] == colon else { return false }
        cursor += 1

        let separatorStart = cursor
        while cursor < lineEnd, buffer[cursor] == space || buffer[cursor] == tab {
            cursor += 1
        }
        guard cursor > separatorStart else { return false }

        // The destination must start with a non-whitespace character; the
        // rest of the line is unconstrained.
        guard cursor < lineEnd, isNonWhitespace(buffer[cursor]) else { return false }

        return hasValidDestinationAndTitle(buffer, from: cursor, to: lineEnd)
    }

    /// A destination (`<…>` or a run of non-spaces) that is followed by nothing or
    /// by a quoted/parenthesised title closing at the end of the line. Free text
    /// after the destination (`[Note]: this is a remark`) is not a definition.
    private static func hasValidDestinationAndTitle(_ buffer: [unichar], from start: Int, to lineEnd: Int) -> Bool {
        guard let destinationEnd = endOfDestination(buffer, from: start, to: lineEnd) else { return false }
        var end = lineEnd
        while end > destinationEnd, buffer[end - 1] == space || buffer[end - 1] == tab {
            end -= 1
        }
        guard destinationEnd < end else { return true }
        var cursor = destinationEnd
        while cursor < end, buffer[cursor] == space || buffer[cursor] == tab {
            cursor += 1
        }
        guard cursor > destinationEnd, end - cursor >= 2 else { return false }
        switch buffer[cursor] {
        case doubleQuote: return buffer[end - 1] == doubleQuote
        case singleQuote: return buffer[end - 1] == singleQuote
        case openParen: return buffer[end - 1] == closeParen
        default: return false
        }
    }

    private static func endOfDestination(_ buffer: [unichar], from start: Int, to lineEnd: Int) -> Int? {
        var cursor = start
        if buffer[cursor] == lessThan {
            while cursor < lineEnd, buffer[cursor] != greaterThan {
                cursor += 1
            }
            return cursor < lineEnd ? cursor + 1 : nil
        }
        while cursor < lineEnd, isNonWhitespace(buffer[cursor]) {
            cursor += 1
        }
        return cursor
    }

    private static func isNonWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return true }
        return !CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
