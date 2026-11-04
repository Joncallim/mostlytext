import Foundation

// MARK: - Line-reordering transforms (EPIC-22 §6.13, Slice 4c-i)

/// Pure, synchronous logic for the four line-reordering built-in transforms
/// (Duplicate/Delete/Move Up/Move Down/Join Lines) — the `MarkdownEditingAssistEngine`
/// precedent applied to whole-line commands: never touches `NSTextView`
/// directly, operates only on `NSString`/`EditorLineIndex`/`EditorSelectionSet`,
/// so every scenario is directly unit-testable without a mounted text view.
/// `EditorTextSystem+LineTransforms.swift` is the thin adapter that calls
/// into this type and applies the resulting `EditorEditTransaction`.
enum EditorLineTransforms {
    /// One contiguous run of logical lines that one or more active
    /// selections/carets touch, after merging every selection whose own
    /// touched line-block overlaps or is merely adjacent to another's
    /// (§6.13's "multi-selection conflict rule": never left to silently
    /// interact by application order).
    struct LineBlockGroup {
        let startLine: Int
        let endLine: Int // inclusive
        /// Indices into the ORIGINAL `EditorSelectionSet.ranges` that
        /// contributed to this group, preserving their original order.
        let memberIndices: [Int]
    }

    // MARK: - Duplicate Line

    static func duplicateLinesTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet
    ) -> EditorEditTransaction? {
        // An empty document is a single empty line; duplicating it would
        // still build a valid but low-value zero-content "edit" that
        // registers an undo step for no visible change -- for consistency
        // with `deleteLinesTransaction`'s own identical guard, decline.
        guard lineIndex.utf16Length > 0 else { return nil }
        let groups = mergedLineBlockGroups(for: selection, lineIndex: lineIndex)
        guard !groups.isEmpty else { return nil }

        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0

        for group in groups {
            let blockStart = lineIndex.lineStartOffsets[group.startLine - 1]
            let blockRange = fullBlockRange(startLine: group.startLine, endLine: group.endLine, lineIndex: lineIndex)
            let blockContent = text.substring(with: blockRange)
            let needsLeadingSeparator = group.endLine == lineIndex.lineCount
            // When duplicating the document's actual last line, a fresh
            // separator has to be synthesized (the block itself has no
            // trailing terminator to reuse) -- reuse the terminator ALREADY
            // used immediately before this block, rather than hardcoding
            // "\n", so a CRLF/CR document's own line-ending style is never
            // silently mixed with a foreign one. Only a single-line document
            // (nothing before the block to infer a style from) falls back
            // to "\n".
            let separator = needsLeadingSeparator
                ? synthesizedSeparator(before: group, lineIndex: lineIndex, text: text)
                : ""
            let replacementText = separator + blockContent
            let insertionPoint = blockRange.location + blockRange.length
            let replacement = TextReplacement(
                range: NSRange(location: insertionPoint, length: 0),
                replacementText: replacementText
            )
            replacements.append(replacement)

            let duplicateStart = insertionPoint + (separator as NSString).length
            for index in group.memberIndices {
                let original = selection.ranges[index]
                let offset = original.location - blockStart
                resultsByOriginalIndex[index] = NSRange(
                    location: duplicateStart + offset + delta,
                    length: original.length
                )
            }

            delta += (replacementText as NSString).length
        }

        // A change that would leave a `\r` directly before an unrelated `\n` (mixed
        // endings) would be read back as one `\r\n`, dropping or inventing a line.
        guard !createsCRLFPair(replacements, in: text) else { return nil }

        return makeTransaction(
            replacements: replacements,
            resultsByOriginalIndex: resultsByOriginalIndex,
            selection: selection,
            undoActionName: String(localized: "Duplicate Line", bundle: .module)
        )
    }

    // MARK: - Delete Line

    static func deleteLinesTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet
    ) -> EditorEditTransaction? {
        // An empty document is a single empty line with nothing to delete --
        // without this guard, "deleting" it would still build a valid but
        // entirely no-op zero-length replacement, contradicting this
        // method's own "returns nil when it would do nothing" contract.
        guard lineIndex.utf16Length > 0 else { return nil }
        let groups = mergedLineBlockGroups(for: selection, lineIndex: lineIndex)
        guard !groups.isEmpty else { return nil }

        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0

        for group in groups {
            let range = deletionRange(
                startLine: group.startLine,
                endLine: group.endLine,
                lineIndex: lineIndex,
                text: text
            )
            replacements.append(TextReplacement(range: range, replacementText: ""))

            let resultLocation = range.location + delta
            for index in group.memberIndices {
                resultsByOriginalIndex[index] = NSRange(location: resultLocation, length: 0)
            }

            delta -= range.length
        }

        // A change that would leave a `\r` directly before an unrelated `\n` (mixed
        // endings) would be read back as one `\r\n`, dropping or inventing a line.
        guard !createsCRLFPair(replacements, in: text) else { return nil }

        return makeTransaction(
            replacements: replacements,
            resultsByOriginalIndex: resultsByOriginalIndex,
            selection: selection,
            undoActionName: String(localized: "Delete Line", bundle: .module)
        )
    }

    // MARK: - Join Lines

    /// Merges the touched block's lines into one: each internal terminator
    /// becomes a single space, and the joined-in line's own leading
    /// whitespace is stripped first (BBEdit/Xcode's shared "Join Lines"
    /// convention). A group already confined to a single line implicitly
    /// joins with the NEXT line (Xcode/BBEdit's own Ctrl-J convention: a
    /// bare caret joins its own line with the one below, not just an
    /// already-multi-line selection) — unless that single line IS the
    /// document's last line, which has no next line to join and is
    /// dropped. If every group drops this way, the whole command is a
    /// no-op, matching Move Up/Down's own all-or-nothing boundary
    /// precedent.
    ///
    /// A disclosed, non-obvious consequence of extending single-line
    /// groups before re-merging: two carets separated by exactly one
    /// UNCLAIMED line (e.g. carets on lines 1 and 3 of a 4-line document)
    /// do not merge in the initial per-selection pass, but each then
    /// extends to claim the line between them, and the re-merge step
    /// correctly detects the resulting overlap — producing ONE whole-span
    /// join across all four lines rather than two independent two-line
    /// joins. This is accepted as a faithful, uniformly-applied consequence
    /// of the merge rule rather than special-cased away; pinned by
    /// `joinTwoCaretsWithAGapMergeIntoOneBlockAfterExtension`.
    static func joinLinesTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet
    ) -> EditorEditTransaction? {
        let initialGroups = mergedLineBlockGroups(for: selection, lineIndex: lineIndex)
        let extended = initialGroups.compactMap { group -> LineBlockGroup? in
            guard group.startLine == group.endLine else { return group }
            guard group.endLine < lineIndex.lineCount else { return nil }
            return LineBlockGroup(
                startLine: group.startLine,
                endLine: group.endLine + 1,
                memberIndices: group.memberIndices
            )
        }
        guard !extended.isEmpty else { return nil }
        // Extending a single-line group by one more line can create a new
        // overlap with an adjacent group (e.g. two carets on consecutive
        // lines) that the original per-selection merge never saw — re-merge.
        let groups = mergeSortedGroups(extended)

        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0

        for group in groups {
            let blockStart = lineIndex.lineStartOffsets[group.startLine - 1]
            // Deliberately NOT the block's own trailing terminator (if any)
            // -- joining never touches what comes after the block.
            let contentEndRange = lineIndex.utf16Range(ofLine: group.endLine, in: text)
            let joinRange = NSRange(
                location: blockStart,
                length: contentEndRange.location + contentEndRange.length - blockStart
            )

            let lines = (group.startLine ... group.endLine).map { text.substring(with: lineIndex.utf16Range(
                ofLine: $0,
                in: text
            )) }
            // The first line is kept as written; each later line loses its leading indentation and is joined with
            // one space. A blank later line adds nothing (no trailing space), and a blank first line does not make
            // the next one "first" and swallow its separator.
            var joined = lines[0]
            for line in lines.dropFirst() {
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                guard !trimmed.isEmpty else { continue }
                joined += joined.isEmpty ? String(trimmed) : " " + trimmed
            }
            replacements.append(TextReplacement(range: joinRange, replacementText: joined))

            // The join point (end of the first line's own original content,
            // now immediately followed by the inserted single space) is
            // where every member's resulting caret lands -- matching
            // BBEdit/Xcode's own "caret sits at the join" convention,
            // rather than trying to preserve each original column across a
            // merge that has no single well-defined post-join column.
            let firstLineContentEnd = lineIndex.utf16Range(ofLine: group.startLine, in: text)
            let joinPoint = firstLineContentEnd.location + firstLineContentEnd.length + delta
            for index in group.memberIndices {
                resultsByOriginalIndex[index] = NSRange(location: joinPoint, length: 0)
            }

            delta += (joined as NSString).length - joinRange.length
        }

        carryOverDroppedSelections(groups: groups, selection: selection, delta: delta, into: &resultsByOriginalIndex)

        // A change that would leave a `\r` directly before an unrelated `\n` (mixed
        // endings) would be read back as one `\r\n`, dropping or inventing a line.
        guard !createsCRLFPair(replacements, in: text) else { return nil }

        return makeTransaction(
            replacements: replacements,
            resultsByOriginalIndex: resultsByOriginalIndex,
            selection: selection,
            undoActionName: String(localized: "Join Lines", bundle: .module)
        )
    }

    // MARK: - Shared helpers

    /// Computes each active selection's own touched line-block, then merges
    /// any two blocks that overlap or are merely adjacent (one block's
    /// `endLine + 1 == the next block's startLine`) into a single group —
    /// §6.13's own "never left to silently interact by application order"
    /// rule, applied once, shared by every transform above. Internal (not
    /// `private`), since `EditorLineTransforms+Move.swift` calls it too.
    static func mergedLineBlockGroups(
        for selection: EditorSelectionSet,
        lineIndex: EditorLineIndex
    ) -> [LineBlockGroup] {
        let perSelectionGroups = selection.ranges.enumerated().map { index, range -> LineBlockGroup in
            let startLine = lineIndex.line(atUTF16Offset: range.location)
            let lastCharacterOffset = range.length > 0 ? range.location + range.length - 1 : range.location
            let endLine = lineIndex.line(atUTF16Offset: lastCharacterOffset)
            return LineBlockGroup(startLine: startLine, endLine: endLine, memberIndices: [index])
        }
        return mergeSortedGroups(perSelectionGroups)
    }

    /// Sorts `groups` by `startLine` and merges any two that overlap or are
    /// merely adjacent (one group's `endLine + 1` reaches the next group's
    /// `startLine`) into one, concatenating `memberIndices` in the merged
    /// group's own ascending-line order. Shared by the initial per-selection
    /// merge above and Join Lines' own post-extension re-merge.
    private static func mergeSortedGroups(_ groups: [LineBlockGroup]) -> [LineBlockGroup] {
        let sorted = groups.sorted { $0.startLine < $1.startLine }
        var merged: [LineBlockGroup] = []
        for group in sorted {
            if let last = merged.last, group.startLine <= last.endLine + 1 {
                merged[merged.count - 1] = LineBlockGroup(
                    startLine: last.startLine,
                    endLine: max(last.endLine, group.endLine),
                    memberIndices: last.memberIndices + group.memberIndices
                )
            } else {
                merged.append(group)
            }
        }
        return merged
    }

    /// The exact terminator text (`"\n"`, `"\r\n"`, or `"\r"`) immediately
    /// after `line`'s own content — i.e. between `line` and `line + 1`.
    /// `line` must not be the document's actual last line (which has no
    /// terminator of its own). Never assume `"\n"`: a CRLF/CR document's
    /// own line-ending style must survive every line-reordering transform
    /// unchanged, exactly as `EditorLineIndex`'s own header comment
    /// describes for the three terminator kinds it recognizes. Internal
    /// (not `private`), since `EditorLineTransforms+Move.swift` calls it
    /// too.
    static func terminatorText(afterLine line: Int, lineIndex: EditorLineIndex, text: NSString) -> String {
        // Every current call site already guarantees `line < lineCount`
        // (the document's actual last line has no terminator to return) --
        // enforced here, not just documented, since an out-of-bounds
        // `lineStartOffsets[line]` would otherwise trap unhelpfully for any
        // future call site that forgets this precondition.
        precondition(
            line < lineIndex.lineCount,
            "terminatorText(afterLine:) requires a line before the document's last"
        )
        let contentEnd = lineIndex.utf16Range(ofLine: line, in: text)
        let terminatorStart = contentEnd.location + contentEnd.length
        let nextLineStart = lineIndex
            .lineStartOffsets[line] // `line` is 1-based; index `line` is the NEXT line's start.
        return text.substring(with: NSRange(location: terminatorStart, length: nextLineStart - terminatorStart))
    }

    /// The UTF-16 range spanning every character of lines `startLine...endLine`
    /// INCLUDING the terminator after `endLine`, if one exists (i.e. if
    /// `endLine` is not the document's last line). Used by transforms that
    /// need to preserve/duplicate the block's own terminator verbatim.
    private static func fullBlockRange(startLine: Int, endLine: Int, lineIndex: EditorLineIndex) -> NSRange {
        let start = lineIndex.lineStartOffsets[startLine - 1]
        let end = endLine < lineIndex.lineCount ? lineIndex.lineStartOffsets[endLine] : lineIndex.utf16Length
        return NSRange(location: start, length: end - start)
    }

    /// The range to DELETE for lines `startLine...endLine`: the block plus
    /// its own trailing terminator when one exists; otherwise (the block
    /// reaches the document's actual last line, which has no terminator of
    /// its own) the PRECEDING line's terminator is swallowed instead, so
    /// deleting the last line never leaves a dangling empty trailing line.
    /// Deleting the entire document (`startLine == 1`) is the third,
    /// simplest case.
    private static func deletionRange(startLine: Int, endLine: Int, lineIndex: EditorLineIndex,
                                      text: NSString) -> NSRange {
        if endLine < lineIndex.lineCount {
            return fullBlockRange(startLine: startLine, endLine: endLine, lineIndex: lineIndex)
        }
        guard startLine > 1 else {
            return NSRange(location: 0, length: lineIndex.utf16Length)
        }
        let precedingLineContent = lineIndex.utf16Range(ofLine: startLine - 1, in: text)
        let precedingLineContentEnd = precedingLineContent.location + precedingLineContent.length
        return NSRange(location: precedingLineContentEnd, length: lineIndex.utf16Length - precedingLineContentEnd)
    }

    /// The separator to put before a duplicated final block: the terminator
    /// already used before the block, else — for a block that starts at line 1 —
    /// the document's first terminator (inside the block itself), and `"\n"`
    /// only for a single-line document with nothing to infer a style from.
    static func synthesizedSeparator(before group: LineBlockGroup, lineIndex: EditorLineIndex,
                                     text: NSString) -> String {
        if group.startLine > 1 {
            return terminatorText(afterLine: group.startLine - 1, lineIndex: lineIndex, text: text)
        }
        return lineIndex.lineCount > 1 ? terminatorText(afterLine: 1, lineIndex: lineIndex, text: text) : "\n"
    }

    /// Builds the final `EditorEditTransaction`, remapping `resultsByOriginalIndex`
    /// back into `EditorSelectionSet.ranges`' own original ordering — every
    /// original index is guaranteed present (every selection belongs to
    /// exactly one group), mirroring `EditorTextSystem+MultiCursor.swift`'s
    /// own "output index i corresponds to input index i" established
    /// convention, so `selection.primaryIndex` carries over unchanged.
    /// Internal (not `private`), since `EditorLineTransforms+Move.swift`
    /// calls it too.
    static func makeTransaction(
        replacements: [TextReplacement],
        resultsByOriginalIndex: [Int: NSRange],
        selection: EditorSelectionSet,
        undoActionName: String
    ) -> EditorEditTransaction? {
        let orderedResults = (0 ..< selection.ranges.count).compactMap { resultsByOriginalIndex[$0] }
        guard orderedResults.count == selection.ranges.count else { return nil }
        let resultingSelection = EditorSelectionSet(ranges: orderedResults, primaryIndex: selection.primaryIndex)
        return EditorEditTransaction(
            replacements: replacements,
            undoActionName: undoActionName,
            resultingSelection: resultingSelection
        )
    }
}
