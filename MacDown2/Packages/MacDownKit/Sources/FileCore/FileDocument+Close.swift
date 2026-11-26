import Foundation

public extension FileDocument {
    /// Marks the document as clean (used after a successful save or discard).
    func markClean() -> FileDocument {
        var copy = self
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    /// Begins the close flow for a dirty document, transitioning to prompting.
    func requestClose() -> (document: FileDocument, resolution: CloseResolution?) {
        var copy = self
        switch state {
        case .clean:
            return (copy, .discard)
        case .dirty:
            copy.state = .promptingClose
            copy.advanceMutation()
            return (copy, nil)
        case .conflict:
            // A conflict has a distinct close flow. Do not erase that fact by
            // converting it to an ordinary dirty-close prompt.
            return (copy, nil)
        case .promptingClose:
            return (copy, nil)
        }
    }

    /// Resolves the close prompt.
    func resolveClose(_ resolution: CloseResolution) -> FileDocument {
        var copy = self
        switch resolution {
        case .save, .discard:
            copy.state = .clean
        case .cancel:
            // Only a document that was actually prompting to close returns to
            // `.dirty`. Guard against dirtying an already-clean document if
            // `resolveClose(.cancel)` is ever called out of the prompt flow.
            copy.state = (state == .promptingClose) ? .dirty : state
        }
        if copy.state != state {
            copy.advanceMutation()
        }
        return copy
    }
}
