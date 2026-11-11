import AppKit
import Foundation

private struct MultiCaretTypingDecision {
    let replacement: TextReplacement?
    let resultingSelection: NSRange
    let undoActionName: String?
}

extension EditorTextSystem {
    /// Applies E10's replacement outcome independently at each selection.
    /// The transaction keeps edits atomic while selection-only type-over
    /// moves can occur without creating a false undo entry.
    func applyMultiCursorTypingAssist(_ text: String, selection: EditorSelectionSet) -> Bool {
        guard text.utf16.count == 1, editingAssistConfiguration.isEnabled,
              let character = text.first
        else { return false }
        let structural = editingAssistConfiguration.completesMatchingCharacters
            && languageEditingProfile.pairedDelimiters.contains {
                $0.opener == character || $0.closer == character
            }
        let markdown = editingAssistConfiguration.completesMarkdownDelimiters
            && (character == "*" || character == "_" || character == "`")
        guard structural || markdown, let source = assistTextSource else { return false }
        let decisions = selection.ranges.map { range in
            typingDecision(text, range: range, source: source)
        }
        let replacements = decisions.compactMap(\.replacement)
        guard EditorEditTransaction.validate(replacements, documentLength: source.length),
              zip(replacements, replacements.dropFirst()).allSatisfy({ $0.range.location <= $1.range.location })
        else { return false }

        var delta = 0
        let mapped = decisions.map { decision -> NSRange in
            let result = NSRange(
                location: decision.resultingSelection.location + delta,
                length: decision.resultingSelection.length
            )
            if let replacement = decision.replacement {
                delta += (replacement.replacementText as NSString).length - replacement.range.length
            }
            return result
        }
        let resultingSelection = EditorSelectionSet(ranges: mapped, primaryIndex: selection.primaryIndex)
        guard !replacements.isEmpty else {
            selectionSet = resultingSelection
            return true
        }
        let names = decisions.compactMap(\.undoActionName)
        let undoName = names.count == replacements.count && Set(names).count == 1
            ? names[0] : String(localized: "Insert", bundle: .module)
        apply(EditorEditTransaction(
            replacements: replacements,
            undoActionName: undoName,
            resultingSelection: resultingSelection
        ))
        return true
    }

    private func typingDecision(_ text: String, range: NSRange, source: NSString) -> MultiCaretTypingDecision {
        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: range, string: text),
            text: source,
            selection: range,
            configuration: editingAssistConfiguration,
            profile: languageEditingProfile
        )
        switch outcome {
        case .passthrough:
            return MultiCaretTypingDecision(
                replacement: TextReplacement(range: range, replacementText: text),
                resultingSelection: NSRange(location: range.location + (text as NSString).length, length: 0),
                undoActionName: nil
            )
        case let .edit(edit):
            return MultiCaretTypingDecision(
                replacement: TextReplacement(range: edit.replacementRange, replacementText: edit.replacementString),
                resultingSelection: edit.resultingSelection,
                undoActionName: edit.undoActionName
            )
        case let .selection(result):
            return MultiCaretTypingDecision(replacement: nil, resultingSelection: result, undoActionName: nil)
        case .handledNoChange:
            return MultiCaretTypingDecision(replacement: nil, resultingSelection: range, undoActionName: nil)
        }
    }
}
