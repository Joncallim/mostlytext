import AppKit

// MARK: - Multi-selection typing/delete (EPIC-22 §6.9, §7.2, Slice 3a)

extension EditorTextSystem {
    /// Called by `EditorTextView.insertText(_:replacementRange:)` — that
    /// override, not `NSTextViewDelegate`'s array-based
    /// `shouldChangeTextInRanges:replacementStrings:`, is the real
    /// interception point. That delegate method was tried first and found,
    /// empirically (`EditorMultiSelectionTests` against a real mounted
    /// `NSTextView`), to never be invoked by ordinary
    /// `insertText(_:replacementRange:)`/`deleteBackward(_:)` regardless of
    /// how many `selectedRanges` are active — AppKit acts only on the
    /// primary selection for a plain keystroke, never fanning it out on its
    /// own.
    ///
    /// `EditorTextSystem.selectionSet` retains synthetic bare carets when
    /// AppKit collapses `selectedRanges` to the primary range. Insertions
    /// can use the same transaction for selected text and zero-length
    /// carets: `EditorEditTransaction` validates and maps both. Deletion at
    /// bare carets needs direction-aware character ranges and remains a
    /// separate follow-up.
    ///
    /// Returns `true` when this method has already applied the edit (the
    /// override must not also call `super`, or the edit would double-apply
    /// at the primary selection and simply not happen at the others);
    /// `false` to fall through to AppKit's normal single-range handling
    /// unchanged — fewer than two active selections (the overwhelmingly
    /// common case, left entirely to AppKit/E10's existing single-range
    /// path), a read-only editor, an active IME composition (fails open,
    /// matching every other IME gate in this
    /// codebase), or a currently-in-progress editing assist/programmatic
    /// text update (this call is itself part of one, so re-entering would
    /// double-apply).
    func applyMultiCursorInsert(_ text: String) -> Bool {
        let selection = selectionSet
        guard selection.ranges.count > 1 else { return false }
        guard textView.isEditable, !textView.hasMarkedText() else { return false }
        guard !isPerformingEditingAssist, !isPerformingProgrammaticTextUpdate else { return false }

        let replacements = selection.ranges.map { TextReplacement(range: $0, replacementText: text) }
        applyMultiCursorTransaction(replacements, primaryIndex: selection.primaryIndex)
        return true
    }

    /// The delete counterpart of `applyMultiCursorInsert(_:)`, called by
    /// both `EditorTextView.deleteBackward(_:)` and `deleteForward(_:)`.
    /// Per that method's doc comment, every range in a `count > 1`
    /// `selectionSet` is EXPECTED to be non-empty, so deleting each
    /// selection's own content is direction-independent — exactly like
    /// pressing either delete key with one ordinary selection active, which
    /// is why there is no separate forward/backward variant here. That
    /// expectation is a live AppKit behavior this codebase does not control,
    /// not a guarantee this type can enforce on its own, so it is checked
    /// (`allSatisfy`) rather than trusted blindly: falling through to
    /// AppKit's native single-range handling if it is ever violated is
    /// strictly safer than silently no-op'ing a zero-length range's delete
    /// keystroke (a swallowed caret) the way an unchecked pass-through
    /// would.
    func applyMultiCursorDeleteSelection() -> Bool {
        let selection = selectionSet
        guard selection.ranges.count > 1, selection.ranges.allSatisfy({ $0.length > 0 }) else { return false }
        guard textView.isEditable, !textView.hasMarkedText() else { return false }
        guard !isPerformingEditingAssist, !isPerformingProgrammaticTextUpdate else { return false }

        let replacements = selection.ranges.map { TextReplacement(range: $0, replacementText: "") }
        applyMultiCursorTransaction(replacements, primaryIndex: selection.primaryIndex)
        return true
    }

    /// Fails open (does nothing) on a `replacements` set
    /// `EditorEditTransaction.validate` rejects, rather than calling
    /// `apply(_:)` with input that method's own Debug-fatal validation
    /// would trap on — this call site guarantees well-formed input instead
    /// of relying on that trap, matching this codebase's established
    /// "fail closed on malformed multi-range input" discipline. In
    /// practice `selectionSet.ranges` is already normalized (sorted,
    /// non-overlapping) by `EditorSelectionSet` itself, so this should
    /// never actually reject; it is defense in depth, not a case this
    /// slice's tests need to force.
    ///
    /// `primaryIndex` is the ORIGINAL (pre-edit) selection's primary index,
    /// not hardcoded to `0`: `replacements` is built directly from
    /// `selectionSet.ranges` (already ascending by location), and
    /// `resultingCaretRanges` sorts by that same ascending location — a
    /// no-op reordering on already-sorted input — so output index *i*
    /// corresponds to input index *i* and the original `primaryIndex`
    /// carries over correctly to the resulting selection.
    private func applyMultiCursorTransaction(_ replacements: [TextReplacement], primaryIndex: Int) {
        let documentLength = textView.textStorage?.length ?? 0
        guard EditorEditTransaction.validate(replacements, documentLength: documentLength) else { return }
        let resultingSelection = EditorSelectionSet(
            ranges: EditorEditTransaction.resultingCaretRanges(for: replacements),
            primaryIndex: primaryIndex
        )
        apply(EditorEditTransaction(replacements: replacements, resultingSelection: resultingSelection))
    }
}
