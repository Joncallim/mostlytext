import AppKit

extension EditorTextSystem {
    /// Above this many ranges a transaction is applied as one native edit. Every per-range `insertText` costs time
    /// proportional to the document, so Replace All was quadratic in its match count (about 4 s for 20k matches,
    /// roughly 80 s for 100k, all on the main thread).
    static let spliceThreshold = 64

    /// Applies disjoint replacements, given highest offset first, as ONE edit over the span from the lowest start to
    /// the highest end, with the untouched text between them carried through. Observers (the Find model's retained
    /// search domain) are still told about every original range, highest first, exactly as the per-range path does.
    func applySpliced(_ descending: [TextReplacement]) {
        guard let first = descending.last, let last = descending.first else { return }
        let source = assistTextSource ?? (text as NSString)
        let span = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        // Build against UTF-16 ranges without repeatedly bridging each large gap back into a Swift String.
        let builder = NSMutableString(capacity: span.length)
        var cursor = span.location
        for replacement in descending.reversed() {
            let gap = NSRange(location: cursor, length: replacement.range.location - cursor)
            builder.append(source.substring(with: gap))
            builder.append(replacement.replacementText)
            cursor = NSMaxRange(replacement.range)
        }
        transactionEditsToReport = descending
        splicedEditPreservesLineBoundaries = !textView.hasMarkedText()
            && lineIndex.utf16Length == source.length
            && descending.allSatisfy { replacement in
                let range = replacement.range
                let end = NSMaxRange(range)
                guard range.location >= 0, end <= source.length, range.length <= 4096,
                      !replacement.replacementText.utf16.contains(where: { $0 == 0x0D || $0 == 0x0A })
                else { return false }
                // A CR/LF pair can be formed or split even when the replaced characters contain no terminator.
                guard range.location == 0 || source.character(at: range.location - 1) != 0x0D,
                      end == source.length || source.character(at: end) != 0x0A
                else { return false }
                for offset in range.location ..< end where source.character(at: offset) == 0x0D
                    || source.character(at: offset) == 0x0A {
                    return false
                }
                return true
            }
        lineIndexNeedsRebuild = true
        isApplyingMultiRangeTransaction = false
        // NSTextView accepts NSString here. Keep the assembled UTF-16 buffer
        // in Foundation instead of materializing a second 1 MB Swift String.
        textView.insertText(builder, replacementRange: span)
        transactionEditsToReport = nil
        splicedEditPreservesLineBoundaries = false
    }

    func reportTransactionEdits(_ edits: [TextReplacement]) {
        for replacement in edits {
            textChangeObserver?(.edit(
                range: replacement.range,
                replacementLength: (replacement.replacementText as NSString).length
            ))
        }
    }
}
