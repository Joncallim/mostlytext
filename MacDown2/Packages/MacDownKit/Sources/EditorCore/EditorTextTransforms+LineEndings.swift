import FileCore
import Foundation

extension EditorTextTransforms {
    /// One terminator occurrence in UTF-16 coordinates.
    private struct Terminator {
        let location: Int
        let length: Int
    }

    /// Converts every line terminator in the whole document to `target` as ONE
    /// replacement spanning the first to the last terminator that differs, so
    /// a large file is a single edit and a single undo step. Content between
    /// terminators is reused verbatim. Returns `nil` when every terminator
    /// already equals `target` (or there are none).
    static func convertLineEndingsTransaction(
        text: NSString,
        selection: EditorSelectionSet,
        target: LineEnding
    ) -> EditorEditTransaction? {
        let targetText = target.text as NSString
        let changed = terminatorsDiffering(from: targetText, in: text)
        guard let first = changed.first, let last = changed.last else { return nil }

        let spanStart = first.location
        let spanEnd = last.location + last.length
        var rebuilt = ""
        var cursor = spanStart
        for terminator in changed {
            rebuilt += text.substring(with: NSRange(location: cursor, length: terminator.location - cursor))
            rebuilt += target.text
            cursor = terminator.location + terminator.length
        }
        rebuilt += text.substring(with: NSRange(location: cursor, length: spanEnd - cursor))
        // Unchanged terminators inside the span were copied as content above.

        let resultingRanges = selection.ranges.map {
            remapPosition($0, throughTerminators: changed, newLength: targetText.length)
        }
        let replacement = TextReplacement(
            range: NSRange(location: spanStart, length: spanEnd - spanStart),
            replacementText: rebuilt
        )
        return EditorEditTransaction(
            replacements: [replacement],
            undoActionName: String(localized: "Convert Line Endings", bundle: .module),
            resultingSelection: EditorSelectionSet(ranges: resultingRanges, primaryIndex: selection.primaryIndex)
        )
    }

    /// Terminators (CRLF counted as one) whose text is not `target`, in
    /// document order.
    private static func terminatorsDiffering(from target: NSString, in text: NSString) -> [Terminator] {
        let length = text.length
        let targetLength = target.length
        let targetFirst = target.character(at: 0)
        var result: [Terminator] = []
        var index = 0
        while index < length {
            let unit = text.character(at: index)
            if unit == 0x0D {
                let isCRLF = index + 1 < length && text.character(at: index + 1) == 0x0A
                let terminatorLength = isCRLF ? 2 : 1
                if !(terminatorLength == targetLength && targetFirst == 0x0D) {
                    result.append(Terminator(location: index, length: terminatorLength))
                }
                index += terminatorLength
            } else if unit == 0x0A {
                if !(targetLength == 1 && targetFirst == 0x0A) {
                    result.append(Terminator(location: index, length: 1))
                }
                index += 1
            } else {
                index += 1
            }
        }
        return result
    }

    /// Maps each endpoint through the terminator length changes in
    /// O(log n) using prefix sums of the replaced lengths. An endpoint that
    /// falls between the CR and LF of a CRLF lands after that terminator's
    /// replacement, so a selection starting there no longer includes it.
    private static func remapPosition(
        _ range: NSRange,
        throughTerminators changed: [Terminator],
        newLength: Int
    ) -> NSRange {
        var replacedLengthBefore = [0]
        replacedLengthBefore.reserveCapacity(changed.count + 1)
        for terminator in changed {
            replacedLengthBefore.append(replacedLengthBefore[replacedLengthBefore.count - 1] + terminator.length)
        }
        func remap(_ offset: Int) -> Int {
            var low = 0
            var high = changed.count
            while low < high {
                let middle = (low + high) / 2
                if changed[middle].location + changed[middle].length <= offset {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return offset + low * newLength - replacedLengthBefore[low]
        }
        let start = remap(range.location)
        let end = remap(range.location + range.length)
        return NSRange(location: start, length: max(0, end - start))
    }
}
