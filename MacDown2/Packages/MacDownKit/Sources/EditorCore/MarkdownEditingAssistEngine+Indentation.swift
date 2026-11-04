import Foundation

// MARK: - Tab / Shift-Tab indentation

extension MarkdownEditingAssistEngine {
    static func tabOutcome(
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile,
        shift: Bool
    ) -> EditingAssistOutcome {
        // A format's own profile can override the global indentation-width
        // preference (EPIC-22 §6.11, Slice 4a); `nil` defers to it exactly
        // as `LanguageEditingProfile.defaultIndentWidth`'s own doc comment
        // already specified back in Slice 1.
        let width = profile.defaultIndentWidth ?? configuration.indentationWidth

        if shift {
            if selection.length > 0 {
                return unindentSelectedLines(text: text, selection: selection, width: width)
            }
            return collapsedUnindent(text: text, caret: selection.location, width: width)
        }

        if selection.length > 0 {
            // With a selection Tab indents its lines — with a tab character when
            // "Insert spaces for Tab" is off — instead of replacing the selection
            // with one tab (native `insertTab:`).
            let unit = configuration.convertsTabsToSpaces ? String(repeating: " ", count: width) : "\t"
            return indentSelectedLines(text: text, selection: selection, unit: unit)
        }
        guard configuration.convertsTabsToSpaces else { return .passthrough }

        // Collapsed Tab: spaces to the next indentation stop.
        let caret = selection.location
        let start = lineStart(of: caret, in: text)
        let column = caret - start
        let spaces = width - (column % width)
        let padding = String(repeating: " ", count: spaces)
        return .edit(EditingAssistEdit(
            replacementRange: NSRange(location: caret, length: 0),
            replacementString: padding,
            resultingSelection: NSRange(location: caret + spaces, length: 0),
            undoActionName: String(localized: "Indent", bundle: .module)
        ))
    }

    private static func indentSelectedLines(text: NSString, selection: NSRange, unit: String) -> EditingAssistOutcome {
        transformSelectedLines(
            text: text,
            selection: selection,
            undoActionName: String(localized: "Indent", bundle: .module)
        ) { lines in
            var deltas: [Int] = []
            let processed = lines.map { line in
                deltas.append(unit.utf16.count)
                return unit + line
            }
            return (processed, deltas)
        }
    }

    private static func unindentSelectedLines(text: NSString, selection: NSRange, width: Int) -> EditingAssistOutcome {
        transformSelectedLines(
            text: text,
            selection: selection,
            undoActionName: String(localized: "Unindent", bundle: .module)
        ) { lines in
            var deltas: [Int] = []
            let processed = lines.map { line in
                if line.hasPrefix("\t") {
                    deltas.append(-1)
                    return String(line.dropFirst())
                }
                let leadingSpaces = line.prefix { $0 == " " }.count
                let remove = min(leadingSpaces, width)
                deltas.append(-remove)
                return String(line.dropFirst(remove))
            }
            return (processed, deltas)
        }
    }

    /// Splits the selected logical line range into real lines, applies a
    /// per-line transform producing per-line UTF-16 deltas, and replaces the
    /// whole range once with a remapped selection.
    static func transformSelectedLines(
        text: NSString,
        selection: NSRange,
        undoActionName: String,
        transform: ([String]) -> (lines: [String], deltas: [Int])
    ) -> EditingAssistOutcome {
        let range = selectedLineRange(text: text, selection: selection)
        let content = text.substring(with: range)
        // Split at LF AND lone CR (a CRLF pair stays one logical line terminator), keeping each exact separator, so a
        // bare-CR or mixed-EOL selection indents/unindents every logical line and rejoins with its original
        // terminators.
        let (pieces, separators) = EditorLineTransforms.logicalLines(of: content)
        let hasSyntheticTrailing = pieces.count > 1 && pieces.last == ""
        let realCount = pieces.count - (hasSyntheticTrailing ? 1 : 0)
        let realLines = Array(pieces.prefix(realCount))

        let (newLines, deltas) = transform(realLines)
        let newContent = EditorLineTransforms.joinLogicalLines(
            hasSyntheticTrailing ? newLines + [""] : newLines,
            separators: separators
        )

        let resultingSelection = absoluteRemappedSelection(
            original: selection,
            rangeLocation: range.location,
            lineLengths: realLines.map(\.utf16.count),
            deltas: deltas,
            newLength: newContent.utf16.count
        )
        return .edit(EditingAssistEdit(
            replacementRange: range,
            replacementString: newContent,
            resultingSelection: resultingSelection,
            undoActionName: undoActionName
        ))
    }

    private static func collapsedUnindent(text: NSString, caret: Int, width: Int) -> EditingAssistOutcome {
        let start = lineStart(of: caret, in: text)
        guard caret > start else { return .passthrough }

        // The caret must be inside the line's leading whitespace. The range is
        // scanned in place on the live source — never materialized as a Swift
        // `String` copy (the line prefix can be the whole document in a
        // pathological single-line file).
        let prefixRange = NSRange(location: start, length: caret - start)
        let isAllWhitespace = text.rangeOfCharacter(
            from: .whitespacesAndNewlines.inverted,
            options: [],
            range: prefixRange
        ).location == NSNotFound
        guard isAllWhitespace else { return .passthrough }

        if character(at: caret - 1, in: text) == 0x09 {
            return .edit(EditingAssistEdit(
                replacementRange: NSRange(location: caret - 1, length: 1),
                replacementString: "",
                resultingSelection: NSRange(location: caret - 1, length: 0),
                undoActionName: String(localized: "Unindent", bundle: .module)
            ))
        }

        let column = caret - start
        let amount = column % width == 0 ? width : column % width
        var trailingSpaces = 0
        var index = caret
        while index > start, character(at: index - 1, in: text) == 0x20 {
            trailingSpaces += 1
            index -= 1
        }
        let remove = min(trailingSpaces, amount)
        guard remove > 0 else { return .passthrough }
        return .edit(EditingAssistEdit(
            replacementRange: NSRange(location: caret - remove, length: remove),
            replacementString: "",
            resultingSelection: NSRange(location: caret - remove, length: 0),
            undoActionName: String(localized: "Unindent", bundle: .module)
        ))
    }

    // MARK: - Selection remap

    /// `remappedSelection`, positioned in the document: the relative result plus `rangeLocation`. The engine's
    /// `EditingAssistEdit.resultingSelection` is absolute, and using the relative value directly put the selection
    /// at the wrong place for any edit not on the first line (Tab on a selection selected `aaa\n   ` instead).
    static func absoluteRemappedSelection(
        original: NSRange,
        rangeLocation: Int,
        lineLengths: [Int],
        deltas: [Int],
        newLength: Int
    ) -> NSRange {
        let relative = remappedSelection(
            original: original,
            rangeLocation: rangeLocation,
            lineLengths: lineLengths,
            deltas: deltas,
            newLength: newLength
        )
        return NSRange(location: rangeLocation + relative.location, length: relative.length)
    }

    /// Maps a selection across a per-line transform using exact UTF-16 deltas.
    static func remappedSelection(
        original: NSRange,
        rangeLocation: Int,
        lineLengths: [Int],
        deltas: [Int],
        newLength: Int
    ) -> NSRange {
        let location = remappedLocation(original.location - rangeLocation, lineLengths: lineLengths, deltas: deltas)
        let end = remappedLocation(
            original.location + original.length - rangeLocation,
            lineLengths: lineLengths,
            deltas: deltas
        )
        let clampedLocation = min(max(0, location), newLength)
        let clampedEnd = min(max(0, end), newLength)
        return NSRange(location: clampedLocation, length: max(0, clampedEnd - clampedLocation))
    }

    /// Maps one UTF-16 position across the per-line deltas: positions inside
    /// a line shift by that line's delta, positions at a line start only by
    /// the deltas of the lines before it.
    static func remappedLocation(_ position: Int, lineLengths: [Int], deltas: [Int]) -> Int {
        var shift = 0
        var lineStart = 0
        for (index, length) in lineLengths.enumerated() {
            let lineEnd = lineStart + length
            if position < lineStart {
                break
            }
            if position == lineStart {
                return position + shift
            }
            if position <= lineEnd {
                // A position inside the removed leading whitespace (negative delta) collapses to the line's start;
                // shifting it by the whole delta would land it on the previous line's terminator, between a CR and
                // its LF in a CRLF document.
                let removable = -min(deltas[index], 0)
                let keptOffset = max(position - lineStart - removable, 0)
                return deltas[index] < 0 ? lineStart + shift + keptOffset : position + shift + deltas[index]
            }
            shift += deltas[index]
            lineStart = lineEnd + 1
        }
        return position + shift
    }

    /// The range covering every line touched by the selection: from the start
    /// of the first line to the content end of the last line, including the
    /// last line's terminating newline when the selection reaches it.
    static func selectedLineRange(text: NSString, selection: NSRange) -> NSRange {
        let start = lineStart(of: selection.location, in: text)
        let lastCharacter = selection.length > 0 ? selection.location + selection.length - 1 : selection.location
        let end = lineContentEnd(of: lastCharacter, in: text)
        var length = end - start
        if end < text.length {
            let separator = character(at: end, in: text)
            let isLF = separator == 0x0A
            let isCRLF = separator == 0x0D && end + 1 < text.length && character(at: end + 1, in: text) == 0x0A
            let isLoneCR = separator == 0x0D && !isCRLF
            if isLF || isCRLF || isLoneCR, selection.location + selection.length > end {
                length += isCRLF ? 2 : 1
            }
        }
        return NSRange(location: start, length: length)
    }
}
