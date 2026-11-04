import Foundation

// MARK: - Markup commands

extension MarkdownEditingAssistEngine {
    static func commandOutcome(
        command: MarkdownEditingCommand,
        text: NSString,
        selection: NSRange
    ) -> EditingAssistOutcome {
        switch command {
        case .bold:
            return toggleInline(
                delimiter: "**",
                text: text,
                selection: selection,
                undoActionName: String(localized: "Bold", bundle: .module)
            )
        case .italic:
            return toggleItalic(text: text, selection: selection)
        case .inlineCode:
            return toggleInline(
                delimiter: "`",
                text: text,
                selection: selection,
                undoActionName: String(localized: "Inline Code", bundle: .module)
            )
        case let .heading(level):
            guard (1 ... 6).contains(level) else { return .passthrough }
            return headingOutcome(level: level, text: text, selection: selection)
        case .paragraph:
            return headingOutcome(level: 0, text: text, selection: selection)
        }
    }

    private static func toggleInline(
        delimiter: String,
        text: NSString,
        selection: NSRange,
        undoActionName: String
    ) -> EditingAssistOutcome {
        let content = text.substring(with: selection)
        if selection.length == 0 {
            return .edit(EditingAssistEdit(
                replacementRange: selection,
                replacementString: delimiter + delimiter,
                resultingSelection: NSRange(location: selection.location + delimiter.utf16.count, length: 0),
                undoActionName: undoActionName
            ))
        }
        if isSurrounded(selection: selection, by: delimiter, in: text) {
            let stripRange = NSRange(
                location: selection.location - delimiter.utf16.count,
                length: selection.length + delimiter.utf16.count * 2
            )
            return .edit(EditingAssistEdit(
                replacementRange: stripRange,
                replacementString: content,
                resultingSelection: NSRange(location: stripRange.location, length: selection.length),
                undoActionName: undoActionName
            ))
        }
        return .edit(EditingAssistEdit(
            replacementRange: selection,
            replacementString: delimiter + content + delimiter,
            resultingSelection: NSRange(location: selection.location + delimiter.utf16.count, length: selection.length),
            undoActionName: undoActionName
        ))
    }

    /// Italic toggle preserves the legacy emphasis ambiguity rule:
    /// `***selection***` counts as surrounded by a single outer `*`, while
    /// `**selection**` alone does not count as single-star italic markup.
    private static func toggleItalic(text: NSString, selection: NSRange) -> EditingAssistOutcome {
        let content = text.substring(with: selection)
        if selection.length == 0 {
            return .edit(EditingAssistEdit(
                replacementRange: selection,
                replacementString: "**",
                resultingSelection: NSRange(location: selection.location + 1, length: 0),
                undoActionName: String(localized: "Italic", bundle: .module)
            ))
        }
        let isTripleSurrounded = isSurrounded(selection: selection, by: "***", in: text)
        let isSingleSurrounded = isSurrounded(selection: selection, by: "*", in: text)
            && !isSurrounded(selection: selection, by: "**", in: text)
        if isTripleSurrounded || isSingleSurrounded {
            let stripRange = NSRange(location: selection.location - 1, length: selection.length + 2)
            return .edit(EditingAssistEdit(
                replacementRange: stripRange,
                replacementString: content,
                resultingSelection: NSRange(location: stripRange.location, length: selection.length),
                undoActionName: String(localized: "Italic", bundle: .module)
            ))
        }
        return .edit(EditingAssistEdit(
            replacementRange: selection,
            replacementString: "*" + content + "*",
            resultingSelection: NSRange(location: selection.location + 1, length: selection.length),
            undoActionName: String(localized: "Italic", bundle: .module)
        ))
    }

    private static func isSurrounded(selection: NSRange, by delimiter: String, in text: NSString) -> Bool {
        let length = delimiter.utf16.count
        guard selection.location >= length,
              selection.location + selection.length + length <= text.length
        else { return false }
        let prefix = text.substring(with: NSRange(location: selection.location - length, length: length))
        let suffix = text.substring(with: NSRange(location: selection.location + selection.length, length: length))
        return prefix == delimiter && suffix == delimiter
    }

    /// Heading 1...6 / Paragraph over every logical line touched by the
    /// selection. Strips one existing ATX prefix, then applies the new level
    /// (Paragraph = no prefix). One replacement over the affected line range.
    private static func headingOutcome(level: Int, text: NSString, selection: NSRange) -> EditingAssistOutcome {
        let range = selectedLineRange(text: text, selection: selection)
        let content = text.substring(with: range)
        let (pieces, separators) = EditorLineTransforms.logicalLines(of: content)
        let hasSyntheticTrailing = pieces.count > 1 && pieces.last == ""
        let realCount = pieces.count - (hasSyntheticTrailing ? 1 : 0)
        let realLines = Array(pieces.prefix(realCount))

        // Paragraph on a blank single line is a deliberate no-op.
        if level == 0, realCount == 1,
           realLines[0].rangeOfCharacter(from: .whitespacesAndNewlines.inverted) == nil
        // swiftlint:disable:next opening_brace
        {
            return .handledNoChange
        }

        var deltas: [Int] = []
        var resultingSelection: NSRange?
        let newLines = realLines.map { line -> String in
            let isBlank = line.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) == nil
            if isBlank {
                if realCount > 1 {
                    // Skip whitespace-only lines inside a multi-line selection.
                    deltas.append(0)
                    return line
                }
                // Blank single line: insert the heading prefix so typing can
                // begin immediately.
                let prefix = String(repeating: "#", count: level) + " "
                resultingSelection = NSRange(location: range.location + prefix.utf16.count, length: 0)
                deltas.append(prefix.utf16.count - line.utf16.count)
                return prefix
            }
            let stripped = strippedATXPrefix(line)
            let newLine = level > 0 ? String(repeating: "#", count: level) + " " + stripped : stripped
            deltas.append(newLine.utf16.count - line.utf16.count)
            return newLine
        }

        let newContent = EditorLineTransforms.joinLogicalLines(
            hasSyntheticTrailing ? newLines + [""] : newLines,
            separators: separators
        )

        let selectionRange = resultingSelection ?? absoluteRemappedSelection(
            original: selection,
            rangeLocation: range.location,
            lineLengths: realLines.map(\.utf16.count),
            deltas: deltas,
            newLength: newContent.utf16.count
        )

        return .edit(EditingAssistEdit(
            replacementRange: range,
            replacementString: newContent,
            resultingSelection: selectionRange,
            undoActionName: level > 0 ? String(localized: "Heading", bundle: .module) : String(
                localized: "Paragraph",
                bundle: .module
            )
        ))
    }

    /// Removes one existing ATX heading prefix (`#` 1...6 followed by at least
    /// one space/tab). Returns the line unchanged when no prefix is present.
    private static func strippedATXPrefix(_ line: String) -> String {
        var hashCount = 0
        for character in line {
            guard character == "#", hashCount < 6 else { break }
            hashCount += 1
        }
        guard hashCount > 0 else { return line }
        let start = line.index(line.startIndex, offsetBy: hashCount)
        guard start < line.endIndex else { return line }
        let after = line[start]
        guard after == " " || after == "\t" else { return line }
        return String(line[line.index(after: start)...])
    }
}
