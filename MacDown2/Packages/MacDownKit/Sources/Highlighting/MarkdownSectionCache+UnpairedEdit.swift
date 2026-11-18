import Foundation

extension MarkdownSectionCache {
    /// Undo/redo may mutate TextKit without the editor's pre-edit callback.
    /// Admit only when the old cached section and the new storage section
    /// differ by one bounded plain-prose edit inside the callback's range.
    /// Any uncertainty leaves the existing full-parse fallback in charge.
    func selectUnpairedPostEdit(postSource: NSString, editedRange: NSRange,
                                delta: Int, visible: NSRange) -> Window? {
        let (expectedLength, overflow) = sourceLength.addingReportingOverflow(delta)
        guard !overflow, expectedLength == postSource.length,
              editedRange.location != NSNotFound, editedRange.location >= 0,
              editedRange.length >= 0, editedRange.location <= postSource.length,
              editedRange.length <= postSource.length - editedRange.location,
              visible.location != NSNotFound, visible.location >= 0,
              visible.length > 0, visible.length <= Self.windowLimit,
              firstIndex(overlapping: visible) != nil,
              let index = indexOfEdit(NSRange(location: editedRange.location, length: 0))
        else { return nil }
        let entry = resolvedSection(at: index)
        let oldWindow = entry.globalRange
        let (newLength, lengthOverflow) = oldWindow.length.addingReportingOverflow(delta)
        let stored = entry.content as NSString
        guard !lengthOverflow, oldWindow.length > 0, oldWindow.length <= Self.windowLimit,
              newLength > 0, newLength <= Self.windowLimit,
              entry.range.location >= 0, entry.range.location <= stored.length,
              entry.range.length <= stored.length - entry.range.location,
              oldWindow.location >= 0, oldWindow.location <= postSource.length,
              newLength <= postSource.length - oldWindow.location,
              editedRange.location >= oldWindow.location,
              NSMaxRange(editedRange) <= oldWindow.location + newLength
        else { return nil }
        let old = stored.substring(with: entry.range) as NSString
        let (oldEdit, newEdit) = Self.changedRanges(old: old, postSource: postSource,
                                                    window: oldWindow, newLength: newLength)
        let window = Window(old: oldWindow,
                            new: NSRange(location: oldWindow.location, length: newLength),
                            firstSection: index, lastSection: index)
        if oldEdit.length == 0 && newEdit.length == 0 {
            // TextKit can report a character edit for a history action that
            // leaves this whole bounded section byte-for-byte unchanged.
            // Reparse only this section to honor the storage notification.
            return delta == 0 && editedRange.length > 0 ? window : nil
        }
        guard editedRange.location <= newEdit.location,
              NSMaxRange(newEdit) <= NSMaxRange(editedRange)
        else { return nil }
        let replacement = postSource.substring(with: newEdit)
        let removed = old.substring(with: oldEdit)
        guard Self.safeProseEdit(old: removed, replacement: replacement),
              oldEdit.length > 0 || Self.isInteriorWordInsertion(source: old, at: oldEdit.location)
              || Self.isInteriorSpaceInsertion(source: old, at: oldEdit.location, replacement: replacement),
              Self.admitsParagraphEdit(
                  entry: entry,
                  localEdit: NSRange(location: entry.range.location + oldEdit.location, length: oldEdit.length)
              )
        else { return nil }
        return window
    }

    private static func changedRanges(old: NSString, postSource: NSString,
                                      window: NSRange, newLength: Int) -> (NSRange, NSRange) {
        var prefix = 0
        while prefix < min(old.length, newLength),
              old.character(at: prefix) == postSource.character(at: window.location + prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(old.length, newLength) - prefix,
              old.character(at: old.length - suffix - 1)
              == postSource.character(at: window.location + newLength - suffix - 1) {
            suffix += 1
        }
        return (
            NSRange(location: prefix, length: old.length - prefix - suffix),
            NSRange(location: window.location + prefix, length: newLength - prefix - suffix)
        )
    }
}
