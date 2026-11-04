import Foundation

// MARK: - Sort/Dedupe/Trim built-in transforms (EPIC-22 §6.13, Slice 4c-ii)

/// Pure, synchronous logic for Sort Lines, Dedupe Lines (Remove Duplicate
/// Lines), and Trim Trailing Whitespace — the `EditorLineTransforms`
/// precedent (Slice 4c-i) applied to this sub-slice's own transforms: never
/// touches `NSTextView`, operates only on `NSString`/`EditorLineIndex`/
/// `EditorSelectionSet`. Reuses `EditorLineTransforms`' own line-block
/// merging (Sort/Dedupe need the identical "expanding a selection to the
/// whole lines it touches can make two originally-disjoint selections
/// overlap" handling Duplicate/Delete already solved) and its
/// `terminatorText(afterLine:)` helper (the CRLF/CR-preservation discipline
/// a hostile review of 4c-i established — every terminator this type
/// touches is reused verbatim from the original text, never synthesized as
/// a hardcoded `"\n"`).
enum EditorTextTransforms {
    // MARK: - Sort Lines

    /// Sorts each qualifying group's own lines by content (case-sensitive,
    /// default `String` ordering), reusing the ORIGINAL positional
    /// terminator sequence rather than trying to keep a terminator "paired"
    /// with the line it followed before sorting — sorting only ever
    /// reorders CONTENT, never the separator structure between positions,
    /// so this is the only model that can't corrupt a mixed- or non-LF-
    /// terminated document (see this type's own header comment).
    ///
    /// A group spanning only one line has nothing to sort and is dropped;
    /// if every group drops this way, the whole command is a no-op —
    /// matching `EditorLineTransforms`' own all-or-nothing boundary
    /// precedent (Move Up/Down, §6.13), applied here at the "not enough
    /// lines to sort" boundary instead.
    static func sortLinesTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet
    ) -> EditorEditTransaction? {
        multiLineGroupTransform(text: text, lineIndex: lineIndex, selection: selection,
                                undoActionName: String(localized: "Sort Lines", bundle: .module)) { block in
            var rebuilt = ""
            for (index, content) in block.contents.sorted().enumerated() {
                rebuilt += content
                if index < block.internalTerminators.count {
                    rebuilt += block.internalTerminators[index]
                }
            }
            return (rebuilt, block.contents.count)
        }
    }

    // MARK: - Dedupe Lines

    /// Removes a later EXACT (case-sensitive) duplicate line, keeping the
    /// first occurrence's own position. Each surviving line's own trailing
    /// terminator is whichever terminator immediately preceded the NEXT
    /// surviving line in the ORIGINAL sequence — a real terminator from the
    /// original text, never fabricated, so a removed line's own terminator
    /// simply vanishes along with it rather than leaving an orphaned
    /// separator or corrupting the document's line-ending style.
    static func dedupeLinesTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet
    ) -> EditorEditTransaction? {
        multiLineGroupTransform(text: text, lineIndex: lineIndex, selection: selection,
                                undoActionName: String(localized: "Dedupe Lines", bundle: .module)) { block in
            // Keyed by UTF-8 bytes: `String` equality would merge canonically
            // equivalent but scalar-distinct lines (#183 F02).
            var seen = Set<[UInt8]>()
            var keptIndices: [Int] = []
            for (index, content) in block.contents.enumerated() where seen.insert(Array(content.utf8)).inserted {
                keptIndices.append(index)
            }
            var rebuilt = ""
            for (position, index) in keptIndices.enumerated() {
                rebuilt += block.contents[index]
                if position < keptIndices.count - 1 {
                    let nextIndex = keptIndices[position + 1]
                    rebuilt += block.internalTerminators[nextIndex - 1]
                }
            }
            return (rebuilt, keptIndices.count)
        }
    }

    // MARK: - Trim Trailing Whitespace

    /// Strips trailing space/tab characters from every line's own content
    /// in the WHOLE document, unconditionally — deliberately NOT selection-
    /// scoped (§6.13: a one-shot cleanup action, matching BBEdit/Sublime's
    /// own shared convention for this specific command), so it never needs
    /// this type's line-block-merge machinery at all. Only lines that
    /// actually have trailing whitespace get a replacement; a document with
    /// none produces zero replacements and this returns `nil`.
    static func trimTrailingWhitespaceTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet
    ) -> EditorEditTransaction? {
        guard lineIndex.utf16Length > 0 else { return nil }

        var replacements: [TextReplacement] = []
        for line in 1 ... lineIndex.lineCount {
            let contentRange = lineIndex.utf16Range(ofLine: line, in: text)
            let content = text.substring(with: contentRange)
            let trimmedLength = (content as NSString).length - trailingWhitespaceLength(of: content)
            guard trimmedLength < (content as NSString).length else { continue }
            let trimRange = NSRange(
                location: contentRange.location + trimmedLength,
                length: contentRange.length - trimmedLength
            )
            replacements.append(TextReplacement(range: trimRange, replacementText: ""))
        }
        guard !replacements.isEmpty else { return nil }
        // Deleting the spaces between a lone `\r` and the `\n` after it would fuse them into one CRLF.
        guard !EditorLineTransforms.createsCRLFPair(replacements, in: text) else { return nil }

        let resultingRanges = selection.ranges.map { remapPosition($0, throughDeletionsIn: replacements) }
        return EditorEditTransaction(
            replacements: replacements,
            undoActionName: String(localized: "Trim Trailing Whitespace", bundle: .module),
            resultingSelection: EditorSelectionSet(ranges: resultingRanges, primaryIndex: selection.primaryIndex)
        )
    }

    /// The number of trailing space/tab UTF-16 units in `line`.
    private static func trailingWhitespaceLength(of line: String) -> Int {
        let line = line as NSString
        var index = line.length
        while index > 0 {
            let unit = line.character(at: index - 1)
            guard unit == 0x20 || unit == 0x09 else { break }
            index -= 1
        }
        return line.length - index
    }

    /// Maps `range` through a set of pure-deletion replacements (each
    /// `replacementText.isEmpty`), clamping any endpoint that fell INSIDE a
    /// deleted span to that span's own start. `replacements` need not be
    /// sorted.
    private static func remapPosition(_ range: NSRange, throughDeletionsIn replacements: [TextReplacement]) -> NSRange {
        func remap(_ offset: Int) -> Int {
            var shifted = offset
            for replacement in replacements.sorted(by: { $0.range.location < $1.range.location }) {
                let deletionEnd = replacement.range.location + replacement.range.length
                if offset >= deletionEnd {
                    shifted -= replacement.range.length
                } else if offset > replacement.range.location {
                    shifted -= (offset - replacement.range.location)
                }
            }
            return shifted
        }
        let start = remap(range.location)
        let end = remap(range.location + range.length)
        return NSRange(location: start, length: max(0, end - start))
    }

    // MARK: - Shared line-block content model

    /// One merged group's own lines, split into content and the terminator
    /// sequence BETWEEN them (`internalTerminators.count == contents.count - 1`)
    /// — deliberately excludes any terminator AFTER the block's own last
    /// line, matching `EditorLineTransforms`' Join Lines "never touch what
    /// comes after" convention, so callers never need to reason about
    /// whether the block reaches the document's actual end.
    private struct LineBlockContent {
        let range: NSRange
        let contents: [String]
        let internalTerminators: [String]
        let memberIndices: [Int]
    }

    /// Shared shape for Sort/Dedupe: merge line-blocks (`EditorLineTransforms`'
    /// own grouping, reused rather than reimplemented), leave any group
    /// confined to a single line untouched (nothing to sort/dedupe; #183 F12),
    /// and apply `transform` to each qualifying group's own content model.
    /// The command is a no-op only when no group spans more than one line.
    private static func multiLineGroupTransform(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet,
        undoActionName: String,
        transform: (LineBlockContent) -> (text: String, lineCount: Int)
    ) -> EditorEditTransaction? {
        let groups = EditorLineTransforms.mergedLineBlockGroups(for: selection, lineIndex: lineIndex)
        guard groups.contains(where: { $0.endLine > $0.startLine }) else { return nil }

        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0

        for group in groups {
            // A group confined to one line has nothing to sort/dedupe: it is
            // left untouched (only shifted by earlier groups' edits) rather
            // than rejecting the whole command alongside multi-line groups.
            guard group.endLine > group.startLine else {
                for index in group.memberIndices {
                    let original = selection.ranges[index]
                    resultsByOriginalIndex[index] = NSRange(
                        location: original.location + delta,
                        length: original.length
                    )
                }
                continue
            }
            let blockStart = lineIndex.lineStartOffsets[group.startLine - 1]
            let lastLineContentRange = lineIndex.utf16Range(ofLine: group.endLine, in: text)
            let range = NSRange(
                location: blockStart,
                length: lastLineContentRange.location + lastLineContentRange.length - blockStart
            )
            let contents = (group.startLine ... group.endLine)
                .map { text.substring(with: lineIndex.utf16Range(ofLine: $0, in: text)) }
            let internalTerminators = (group.startLine ..< group.endLine)
                .map { EditorLineTransforms.terminatorText(afterLine: $0, lineIndex: lineIndex, text: text) }
            let block = LineBlockContent(
                range: range,
                contents: contents,
                internalTerminators: internalTerminators,
                memberIndices: group.memberIndices
            )

            let (rebuilt, expectedLineCount) = transform(block)
            // Reordering or removing lines of a document that mixes `\r` and `\n`
            // terminators can leave a `\r` directly before an unrelated `\n`, which the
            // next parse reads as ONE `\r\n` (a line vanishes, terminators are rewritten).
            // No faithful result exists, so the command declines (invariant 5).
            guard EditorLineIndex(text: rebuilt as NSString).lineCount == expectedLineCount else { return nil }
            replacements.append(TextReplacement(range: range, replacementText: rebuilt))

            let resultLocation = range.location + delta
            for index in group.memberIndices {
                resultsByOriginalIndex[index] = NSRange(location: resultLocation, length: 0)
            }

            delta += (rebuilt as NSString).length - range.length
        }

        guard !EditorLineTransforms.createsCRLFPair(replacements, in: text) else { return nil }

        return EditorLineTransforms.makeTransaction(
            replacements: replacements,
            resultsByOriginalIndex: resultsByOriginalIndex,
            selection: selection,
            undoActionName: undoActionName
        )
    }
}
