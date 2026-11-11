import AppKit
import Foundation

enum MultiCursorDeleteDirection {
    case backward
    case forward
}

extension EditorTextSystem {
    /// Deletes selected text or one composed character at each synthetic bare
    /// caret. All ranges refer to the same pre-edit text and publish as one
    /// transaction. A caret at a document boundary stays put while the other
    /// carets still edit; overlapping grapheme ranges are merged before the
    /// transaction so the same character is never deleted twice.
    func applyMultiCursorDelete(_ direction: MultiCursorDeleteDirection) -> Bool {
        let selection = selectionSet
        guard selection.isMultiple, textView.isEditable, !textView.hasMarkedText(),
              !isPerformingEditingAssist, !isPerformingProgrammaticTextUpdate,
              let source = assistTextSource
        else { return false }

        let candidates = selection.ranges.map { range -> NSRange in
            guard range.length == 0 else { return range }
            return Self.deleteRange(at: range.location, direction: direction, in: source)
        }
        let deletions = Self.mergedDeleteRanges(candidates.filter { $0.length > 0 })
        guard !deletions.isEmpty else { return true }
        let replacements = deletions.map { TextReplacement(range: $0, replacementText: "") }
        guard EditorEditTransaction.validate(replacements, documentLength: source.length) else { return false }

        let carets = zip(selection.ranges, candidates).map { original, candidate in
            let target = candidate.length > 0 ? candidate.location : original.location
            return NSRange(location: Self.offsetAfterDeletes(target, ranges: deletions), length: 0)
        }
        let resultingSelection = EditorSelectionSet(ranges: carets, primaryIndex: selection.primaryIndex)
        apply(EditorEditTransaction(replacements: replacements, resultingSelection: resultingSelection))
        return true
    }

    private static func mergedDeleteRanges(_ ranges: [NSRange]) -> [NSRange] {
        var merged: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            if let previous = merged.last, range.location < NSMaxRange(previous) {
                merged[merged.count - 1] = NSRange(
                    location: previous.location,
                    length: max(NSMaxRange(previous), NSMaxRange(range)) - previous.location
                )
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func deleteRange(
        at caret: Int,
        direction: MultiCursorDeleteDirection,
        in source: NSString
    ) -> NSRange {
        let index: Int
        switch direction {
        case .backward:
            guard caret > 0 else { return NSRange(location: caret, length: 0) }
            index = caret - 1
        case .forward:
            guard caret < source.length else { return NSRange(location: caret, length: 0) }
            index = caret
        }
        // Foundation's composed-character API treats CR and LF separately.
        // The editor's line-ending invariant requires deleting the pair as
        // one separator, including a caret placed between its two units.
        if source.character(at: index) == 0x0A, index > 0, source.character(at: index - 1) == 0x0D {
            return NSRange(location: index - 1, length: 2)
        }
        if source.character(at: index) == 0x0D, index + 1 < source.length,
           source.character(at: index + 1) == 0x0A {
            return NSRange(location: index, length: 2)
        }
        return source.rangeOfComposedCharacterSequence(at: index)
    }

    private static func offsetAfterDeletes(_ offset: Int, ranges: [NSRange]) -> Int {
        var removed = 0
        for range in ranges {
            if offset < range.location {
                break
            }
            if offset < NSMaxRange(range) {
                return range.location - removed
            }
            removed += range.length
        }
        return offset - removed
    }
}
