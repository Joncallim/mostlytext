import AppKit
import Foundation

extension EditorTextSystem {
    /// Applies one Return command at every selection using each line's own
    /// separator and, when enabled, its own Markdown/general editing assist.
    /// An assist that would overlap another caret falls back to plain newline
    /// insertion for the whole set instead of partly applying a command.
    func applyMultiCursorNewline(usingEditingAssists: Bool) -> Bool {
        let selection = selectionSet
        guard selection.isMultiple, textView.isEditable, canApplyCommandEdit,
              let source = assistTextSource
        else { return false }
        guard selection.ranges.allSatisfy({ range in
            range.location >= 0 && range.length >= 0 && range.location <= source.length
                && range.length <= source.length - range.location
        }) else { return false }

        let plain = selection.ranges.map { range in
            TextReplacement(
                range: range,
                replacementText: MarkdownEditingAssistEngine.lineSeparator(ofLineContaining: range.location, in: source)
            )
        }
        guard EditorEditTransaction.validate(plain, documentLength: source.length) else { return false }

        let (assisted, assistNames) = usingEditingAssists
            ? assistedNewlineReplacements(selection: selection, source: source, fallback: plain)
            : ([], [])

        let useAssisted = usingEditingAssists
            && EditorEditTransaction.validate(assisted, documentLength: source.length)
        let replacements = useAssisted ? assisted : plain
        let undoName = useAssisted && assistNames.count == selection.count && Set(assistNames).count == 1
            ? assistNames[0] : String(localized: "Insert", bundle: .module)
        let resultingSelection = EditorSelectionSet(
            ranges: EditorEditTransaction.resultingCaretRanges(for: replacements),
            primaryIndex: selection.primaryIndex
        )
        apply(EditorEditTransaction(
            replacements: replacements,
            undoActionName: undoName,
            resultingSelection: resultingSelection
        ))
        return true
    }

    private func assistedNewlineReplacements(
        selection: EditorSelectionSet,
        source: NSString,
        fallback: [TextReplacement]
    ) -> ([TextReplacement], [String]) {
        var replacements: [TextReplacement] = []
        var names: [String] = []
        for (range, plain) in zip(selection.ranges, fallback) {
            let outcome = MarkdownEditingAssistEngine.outcome(
                for: .insertNewline,
                text: source,
                selection: range,
                configuration: editingAssistConfiguration,
                profile: languageEditingProfile
            )
            if case let .edit(edit) = outcome,
               edit.resultingSelection == NSRange(
                   location: edit.replacementRange.location + (edit.replacementString as NSString).length,
                   length: 0
               ) {
                replacements.append(TextReplacement(
                    range: edit.replacementRange,
                    replacementText: edit.replacementString
                ))
                names.append(edit.undoActionName)
            } else {
                replacements.append(plain)
            }
        }
        return (replacements, names)
    }
}
