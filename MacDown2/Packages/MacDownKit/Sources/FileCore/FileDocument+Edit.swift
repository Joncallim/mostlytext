import Foundation

// MARK: - Text mutation

public extension FileDocument {
    /// Returns a new document with `text` updated and the dirty flag set.
    ///
    /// Use this method for **user edits**. Unlike `updatingText`, this method
    /// always transitions a `.clean` document to `.dirty`, even when the new text
    /// is identical to the current text. This matches NSTextView's behavior,
    /// where any editing transaction (including a no-op keystroke) marks the
    /// document as edited.
    func edited(text newText: String) -> FileDocument {
        var copy = self
        copy.text = newText
        copy.unavailableCleanText = nil
        switch copy.state {
        case .clean:
            copy.state = .dirty
        case .dirty, .conflict:
            break
        case .promptingClose:
            // If the user edits while being prompted, return to dirty.
            copy.state = .dirty
        }
        copy.advanceMutation()
        return copy
    }
}
