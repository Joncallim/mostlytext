import AppKit

extension EditorView.Coordinator {
    /// The Return-family selectors that insert a line break.
    nonisolated static func isNewlineSelector(_ selector: Selector) -> Bool {
        selector == #selector(NSResponder.insertNewline(_:))
            || selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            || selector == #selector(NSResponder.insertLineBreak(_:))
            || selector == #selector(NSResponder.insertParagraphSeparator(_:))
    }

    /// A Return that no assist handles would let AppKit insert a bare `\n`,
    /// adding a second line-ending convention to a CRLF (or bare-CR) document
    /// — invariant #5. When the document's own separator is not `\n`, insert
    /// that separator instead (over every range of a multi-selection). The
    /// Markdown assist outcome for plain Return is applied here when it is not
    /// a passthrough, so it is computed once. Fails open for IME composition,
    /// read-only editors and the programmatic-update guards.
    @MainActor
    func handleLineEndingAwareNewline(
        _ textView: NSTextView,
        system: EditorTextSystem,
        selector: Selector
    ) -> Bool {
        guard !isApplyingModelText,
              !system.isPerformingProgrammaticTextUpdate,
              !system.isPerformingEditingAssist,
              !textView.hasMarkedText(),
              textView.isEditable,
              let source = system.assistTextSource
        else { return false }
        let selection = system.selectedRange
        let separator = MarkdownEditingAssistEngine.lineSeparator(ofLineContaining: selection.location, in: source)
        // Multiple selections and bare carets fan out in LF documents too:
        // AppKit's `insertNewline:` targets only the primary range.
        if separator == "\n", system.selectionSet.isMultiple, system.applyMultiCursorInsert(separator) {
            return true
        }
        guard separator != "\n" else { return false }
        if selector == #selector(NSResponder.insertNewline(_:)), system.editingAssistConfiguration.isEnabled {
            let outcome = MarkdownEditingAssistEngine.outcome(
                for: .insertNewline,
                text: source,
                selection: selection,
                configuration: system.editingAssistConfiguration,
                profile: system.languageEditingProfile
            )
            if outcome != .passthrough {
                return system.applyAssistOutcome(outcome)
            }
        }
        // Real selections and synthetic bare carets fan out through the same
        // transaction. Native input would otherwise edit only the primary.
        if system.selectionSet.isMultiple, system.applyMultiCursorInsert(separator) {
            return true
        }
        return system.applyAssistOutcome(.edit(EditingAssistEdit(
            replacementRange: selection,
            replacementString: separator,
            resultingSelection: NSRange(location: selection.location + separator.utf16.count, length: 0),
            undoActionName: String(localized: "Typing", bundle: .module)
        )))
    }

    /// Tab / Shift-Tab with several selections indent / outdent the lines of EVERY selection (one transaction), not
    /// only the primary's. `nil` for any other selector.
    @MainActor
    func handleMultiSelectionTab(_ selector: Selector, system: EditorTextSystem) -> Bool? {
        switch selector {
        case #selector(NSResponder.insertTab(_:)): system.increaseIndent()
        case #selector(NSResponder.insertBacktab(_:)): system.decreaseIndent()
        default: nil
        }
    }
}
