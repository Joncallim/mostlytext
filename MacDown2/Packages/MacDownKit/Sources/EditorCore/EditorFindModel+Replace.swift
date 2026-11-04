import FileCore
import Foundation
import TextSearch

// MARK: - Replace / Replace All (EPIC-22 §6.14, Slice 5b)

public extension EditorFindModel {
    /// Builds the transaction that replaces just the CURRENT match with
    /// `replacement`, or `nil` if there is no current match. Per §6.14
    /// ("Replace/Replace All route through `EditorEditTransaction`
    /// unchanged... N == 1 is a valid, and encouraged, use of this type"),
    /// this is simply the one-replacement case of the same mechanism
    /// `replaceAllTransaction(with:)` below uses for N.
    ///
    /// Matches this type's own "never mutates live text" contract (see the
    /// type's own doc comment above): this is a pure data transformation
    /// over the already-computed `matches`/`currentMatch`, not an edit. The
    /// caller applies the returned transaction via
    /// `EditorTextSystem.apply(_:)` — the only thing that actually mutates
    /// the document — then re-runs `updateMatches(in:)` against the
    /// POST-edit text, since every match after the replaced one has shifted
    /// and the replacement itself may have changed which text still
    /// matches at all.
    func replaceCurrentTransaction(with replacement: String) -> EditorEditTransaction? {
        guard let match = currentMatch else { return nil }
        let textReplacement = TextReplacement(
            range: match.range,
            replacementText: LineEnding.adaptingLineBreaks(in: replacement, to: searchedLineEnding)
        )
        guard let caretRange = EditorEditTransaction.resultingCaretRanges(for: [textReplacement]).first else {
            return nil
        }
        return EditorEditTransaction(
            replacements: [textReplacement],
            undoActionName: String(localized: "Replace", bundle: .module),
            resultingSelection: EditorSelectionSet(single: caretRange)
        )
    }

    /// Builds ONE transaction replacing EVERY current match with
    /// `replacement` — one undo group, one publication, per §4 invariant
    /// #10 ("a multi-cursor edit affecting N ranges is one undo step, not
    /// N"), never N separate transactions. Returns `nil` if there are no
    /// matches. The resulting caret lands right after the LAST (highest
    /// document-offset) replacement — an unsurprising "you finished at the
    /// last thing that changed" convention, and the one position
    /// `resultingCaretRanges(for:)` already computes for free.
    func replaceAllTransaction(with replacement: String) -> EditorEditTransaction? {
        guard !matches.isEmpty else { return nil }
        let adapted = LineEnding.adaptingLineBreaks(in: replacement, to: searchedLineEnding)
        let textReplacements = matches.map { TextReplacement(range: $0.range, replacementText: adapted) }
        guard let caretRange = EditorEditTransaction.resultingCaretRanges(for: textReplacements).last else {
            return nil
        }
        return EditorEditTransaction(
            replacements: textReplacements,
            undoActionName: String(localized: "Replace All", bundle: .module),
            resultingSelection: EditorSelectionSet(single: caretRange)
        )
    }
}
