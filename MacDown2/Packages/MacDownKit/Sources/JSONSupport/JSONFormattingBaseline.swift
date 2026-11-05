import Foundation

/// The state captured when a Format JSON command is issued (EPIC-11 §3.5).
///
/// A formatting computation runs off the main actor; its result is applied
/// only when the document and editor still match this baseline when the
/// computation completes. An edit during formatting, an external reload
/// (even one with identical text), or any document state transition rejects
/// the stale result — the user's newer content is never overwritten.
public struct JSONFormattingBaseline: Sendable, Equatable {
    /// The immutable text snapshot the formatting computation started from.
    public let text: String
    /// `FileDocument.mutationGeneration` at command time. Advances on every
    /// visible document-state transition, including external reconciliation
    /// that happens to restore identical text.
    public let documentGeneration: UInt
    /// `EditorTextSystem.contentRevision` at command time. Advances on every
    /// editor text edit, including newline-only edits that do not change the
    /// string.
    public let editorContentRevision: UInt64
    /// The formatting options the command was issued with.
    public let options: JSONFormatOptions

    public init(
        text: String,
        documentGeneration: UInt,
        editorContentRevision: UInt64,
        options: JSONFormatOptions
    ) {
        self.text = text
        self.documentGeneration = documentGeneration
        self.editorContentRevision = editorContentRevision
        self.options = options
    }

    /// Whether a completion may still apply: the editor text, the document
    /// generation, and the editor content revision must all match the values
    /// captured when the command was issued.
    public func accepts(text: String, documentGeneration: UInt, editorContentRevision: UInt64) -> Bool {
        // String equality accepts canonically equivalent Unicode spellings;
        // formatting may only replace the exact authored snapshot.
        text.utf8.elementsEqual(self.text.utf8)
            && documentGeneration == self.documentGeneration
            && editorContentRevision == self.editorContentRevision
    }
}
