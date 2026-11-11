import AppKit
import Foundation

private struct MultiCursorCommandPlan {
    let replacements: [TextReplacement]
    let resultingSelection: EditorSelectionSet
    let undoActionName: String?
}

extension EditorTextSystem {
    /// Applies one explicit Markdown command across the whole selection set.
    /// Identical expanded line edits (two carets on one heading line) publish
    /// once; incompatible overlaps decline atomically rather than editing
    /// only the primary selection.
    func applyMultiCursorMarkdownCommand(_ command: MarkdownEditingCommand, source: NSString) -> Bool {
        let selection = selectionSet
        guard selection.isMultiple, textView.isEditable else { return false }
        guard selection.ranges.allSatisfy({ range in
            range.location >= 0 && range.length >= 0 && range.location <= source.length
                && range.length <= source.length - range.location
        }) else { return false }

        let outcomes = selection.ranges.map { range in
            MarkdownEditingAssistEngine.outcome(
                for: .markdownCommand(command),
                text: source,
                selection: range,
                configuration: editingAssistConfiguration,
                profile: languageEditingProfile
            )
        }
        guard let plan = Self.commandPlan(selection: selection, outcomes: outcomes, length: source.length) else {
            return false
        }
        guard !plan.replacements.isEmpty else {
            selectionSet = plan.resultingSelection
            return true
        }
        apply(EditorEditTransaction(
            replacements: plan.replacements,
            undoActionName: plan.undoActionName,
            resultingSelection: plan.resultingSelection
        ))
        return true
    }

    private static func commandPlan(
        selection: EditorSelectionSet,
        outcomes: [EditingAssistOutcome],
        length: Int
    ) -> MultiCursorCommandPlan? {
        var replacements: [TextReplacement] = []
        var mapped: [NSRange] = []
        var delta = 0
        var previous: (replacement: TextReplacement, shift: Int)?
        var undoName: String?
        for (original, outcome) in zip(selection.ranges, outcomes) {
            switch outcome {
            case let .edit(edit):
                let replacement = TextReplacement(range: edit.replacementRange, replacementText: edit.replacementString)
                let shift: Int
                if let previous, previous.replacement == replacement {
                    shift = previous.shift
                } else {
                    shift = delta
                    replacements.append(replacement)
                    previous = (replacement, shift)
                    delta += (replacement.replacementText as NSString).length - replacement.range.length
                }
                mapped.append(NSRange(
                    location: edit.resultingSelection.location + shift,
                    length: edit.resultingSelection.length
                ))
                undoName = undoName ?? edit.undoActionName
            case let .selection(result):
                mapped.append(NSRange(location: result.location + delta, length: result.length))
                previous = nil
            case .handledNoChange:
                mapped.append(NSRange(location: original.location + delta, length: original.length))
                previous = nil
            case .passthrough:
                return nil
            }
        }
        guard EditorEditTransaction.validate(replacements, documentLength: length),
              zip(replacements, replacements.dropFirst()).allSatisfy({ $0.range.location <= $1.range.location })
        else { return nil }
        return MultiCursorCommandPlan(
            replacements: replacements,
            resultingSelection: EditorSelectionSet(ranges: mapped, primaryIndex: selection.primaryIndex),
            undoActionName: undoName
        )
    }
}
