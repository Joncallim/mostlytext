import AppKit

/// Sits in `NSTextStorage.delegate` in front of Neon's own storage delegate
/// and decides, per character edit, whether Neon hears about it (register row
/// H5's size fallback).
///
/// Why here: Neon's `TextViewHighlighter` learns of an edit only through the
/// storage delegate. Its `willProcessEditing` only records the edit; its
/// `didProcessEditing` runs the reparse — synchronously on the main thread for
/// an edit under 2,048 UTF-16 units ending before offset 1,048,576. Both run
/// inside `processEditing`, after the characters changed, so
/// `textStorage.length` is already the post-edit length. Deciding in
/// `willProcessEditing`, before either Neon callback, means an edit that takes
/// the document past the cut-off is never forwarded: Neon does no work for it
/// at all. Will and did are always forwarded as a pair (Neon buffers between
/// them), and attribute-only edits pass straight through (Neon ignores them).
@MainActor
final class HighlightingStorageGate: NSObject, NSTextStorageDelegate {
    /// Neon's storage delegate while full highlighting is attached. Weak: the
    /// `TextViewHighlighter` owns it, and dropping the highlighter must not
    /// leave a live delegate behind.
    weak var downstream: NSTextStorageDelegate?
    /// Whatever was the storage's delegate before this gate was installed;
    /// told about every edit and restored by ``uninstall(from:)``.
    private weak var previous: NSTextStorageDelegate?
    /// Asked once per character edit, in `willProcessEditing`, with the
    /// post-edit length: `true` forwards the edit to ``downstream``.
    var shouldForwardEdit: (_ postEditLength: Int) -> Bool = { _ in true }
    /// Told after every character edit has been processed (forwarded or not).
    var didProcessCharacterEdit: (_ postEditLength: Int) -> Void = { _ in }
    /// Actual post-mutation geometry for a future bounded Markdown adapter.
    /// `editedRange` addresses the new storage, and `delta` is its UTF-16
    /// length change. A pre-edit proposal is useful only when it matches this
    /// callback; undo, composition and programmatic edits can lack one.
    var didProcessCharacterEditWithGeometry: ((_ editedRange: NSRange, _ delta: Int,
                                               _ postEditLength: Int) -> Void)?

    private var forwardsCurrentEdit = true
    /// Character edits seen and forwarded. Lets tests prove that an edit was
    /// withheld from Neon rather than inferring it from timing.
    private(set) var characterEditCount = 0
    private(set) var forwardedCharacterEditCount = 0

    /// Becomes the delegate of `storage`, remembering any existing delegate.
    func install(on storage: NSTextStorage) {
        if storage.delegate !== self {
            previous = storage.delegate
            storage.delegate = self
        }
    }

    /// Re-takes the delegate slot after Neon installed its own, keeping Neon's
    /// as ``downstream``.
    func adoptDownstream(from storage: NSTextStorage) {
        if let current = storage.delegate, current !== self {
            downstream = current
        }
        storage.delegate = self
    }

    /// Hands the delegate slot back to whatever held it before ``install(on:)``.
    func uninstall(from storage: NSTextStorage) {
        downstream = nil
        if storage.delegate === self {
            storage.delegate = previous
        }
    }

    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // NSTextStorage calls its delegate on the thread that edits it; the
        // editor's storage is only ever edited on the main thread.
        nonisolated(unsafe) let textStorage = textStorage
        MainActor.assumeIsolated {
            if editedMask.contains(.editedCharacters) {
                characterEditCount += 1
                forwardsCurrentEdit = downstream != nil && shouldForwardEdit(textStorage.length)
                if forwardsCurrentEdit {
                    forwardedCharacterEditCount += 1
                }
            } else {
                forwardsCurrentEdit = true
            }
            previous?.textStorage?(
                textStorage,
                willProcessEditing: editedMask,
                range: editedRange,
                changeInLength: delta
            )
            if forwardsCurrentEdit {
                downstream?.textStorage?(
                    textStorage, willProcessEditing: editedMask, range: editedRange, changeInLength: delta
                )
            }
        }
    }

    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        nonisolated(unsafe) let textStorage = textStorage
        MainActor.assumeIsolated {
            previous?.textStorage?(
                textStorage,
                didProcessEditing: editedMask,
                range: editedRange,
                changeInLength: delta
            )
            if forwardsCurrentEdit {
                downstream?.textStorage?(
                    textStorage, didProcessEditing: editedMask, range: editedRange, changeInLength: delta
                )
            }
            forwardsCurrentEdit = true
            if editedMask.contains(.editedCharacters) {
                didProcessCharacterEditWithGeometry?(editedRange, delta, textStorage.length)
                didProcessCharacterEdit(textStorage.length)
            }
        }
    }
}
