import Foundation

// MARK: - Move Line Up / Down (EPIC-22 §6.13, Slice 4c-i)

/// Extracted from `EditorLineTransforms.swift` to stay under swiftlint's
/// type-body-length limit once Duplicate/Delete/Join were also added there.
extension EditorLineTransforms {
    static func moveLinesUpTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet
    ) -> EditorEditTransaction? {
        moveLinesTransaction(text: text, lineIndex: lineIndex, selection: selection, moveUp: true)
    }

    static func moveLinesDownTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet
    ) -> EditorEditTransaction? {
        moveLinesTransaction(text: text, lineIndex: lineIndex, selection: selection, moveUp: false)
    }

    /// Every active group must have room to move in the requested direction
    /// (all-or-nothing, matching this codebase's established "the whole
    /// command disables/no-ops rather than silently half-applying" — §6.13
    /// — precedent for Sort/Dedupe/case conversion).
    private static func moveLinesTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet,
        moveUp: Bool
    ) -> EditorEditTransaction? {
        let groups = mergedLineBlockGroups(for: selection, lineIndex: lineIndex)
        guard !groups.isEmpty else { return nil }
        guard moveUp
            ? groups.allSatisfy({ $0.startLine > 1 })
            : groups.allSatisfy({ $0.endLine < lineIndex.lineCount })
        else { return nil }

        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0

        for group in groups {
            let blockStart = lineIndex.lineStartOffsets[group.startLine - 1]
            let (replacement, blockOffsetInNewContent) = swapReplacement(
                startLine: group.startLine,
                endLine: group.endLine,
                moveUp: moveUp,
                lineIndex: lineIndex,
                text: text
            )
            replacements.append(replacement)

            let newBlockStart = replacement.range.location + blockOffsetInNewContent
            for index in group.memberIndices {
                let original = selection.ranges[index]
                let offset = original.location - blockStart
                resultsByOriginalIndex[index] = NSRange(
                    location: newBlockStart + offset + delta,
                    length: original.length
                )
            }

            delta += (replacement.replacementText as NSString).length - replacement.range.length
        }

        // Swapping lines in a document that mixes `\r` and `\n` terminators can
        // leave a moved `\r` directly in front of an unrelated `\n` (an empty line
        // between them), which the next parse reads as ONE `\r\n`: a line would
        // vanish and the terminators would be silently rewritten. Such a move has
        // no faithful representation, so it declines instead (invariant 5).
        guard !createsCRLFPair(replacements, in: text), !fusesInsideReplacement(replacements, in: text) else {
            return nil
        }

        return makeTransaction(
            replacements: replacements,
            resultsByOriginalIndex: resultsByOriginalIndex,
            selection: selection,
            undoActionName: moveUp ? String(localized: "Move Line Up", bundle: .module) : String(
                localized: "Move Line Down",
                bundle: .module
            )
        )
    }

    /// A swap keeps every terminator but can put a `\r` next to a `\n` INSIDE the replacement text
    /// (`blockJoined + adjacentTerminator + adjacentContent`), which `createsCRLFPair` — it only looks at
    /// seams at replacement edges — cannot see. A swap must never create more CRLF pairs than it replaced.
    static func fusesInsideReplacement(_ replacements: [TextReplacement], in text: NSString) -> Bool {
        func pairs(_ string: String) -> Int {
            let units = Array(string.utf16)
            return units.count < 2 ? 0 : (1 ..< units.count).count { units[$0 - 1] == 0x0D && units[$0] == 0x0A }
        }
        return replacements.contains { pairs($0.replacementText) > pairs(text.substring(with: $0.range)) }
    }

    /// Whether applying `replacements` (ascending, non-overlapping) would place a
    /// `\r` immediately before a `\n` where the original text had no such pair at
    /// that seam. Only seams at replacement edges can change, so only those are
    /// examined, with a neighbouring replacement's text standing in for the original
    /// character when two replacements touch. A deletion (empty replacement) joins
    /// the characters on either side of it directly.
    static func createsCRLFPair(_ replacements: [TextReplacement], in text: NSString) -> Bool {
        let carriageReturn = unichar(0x000D)
        let lineFeed = unichar(0x000A)
        func lastUnit(_ string: String) -> unichar? {
            let nsString = string as NSString
            return nsString.length > 0 ? nsString.character(at: nsString.length - 1) : nil
        }
        func firstUnit(_ string: String) -> unichar? {
            let nsString = string as NSString
            return nsString.length > 0 ? nsString.character(at: 0) : nil
        }
        for (index, replacement) in replacements.enumerated() {
            let start = replacement.range.location
            let end = NSMaxRange(replacement.range)

            let before: unichar? = if index > 0, NSMaxRange(replacements[index - 1].range) == start {
                lastUnit(replacements[index - 1].replacementText)
            } else if start > 0 {
                text.character(at: start - 1)
            } else {
                nil
            }
            let nextTouches = index + 1 < replacements.count && replacements[index + 1].range.location == end
            let after: unichar? = if nextTouches {
                firstUnit(replacements[index + 1].replacementText)
            } else if end < text.length {
                text.character(at: end)
            } else {
                nil
            }

            let first = firstUnit(replacement.replacementText)
            let last = lastUnit(replacement.replacementText)
            if first == nil {
                // Deleted span: its neighbours become adjacent (a touching successor
                // checks its own leading seam against what precedes it here).
                if before == carriageReturn, after == lineFeed, !nextTouches {
                    return true
                }
                continue
            }
            if before == carriageReturn, first == lineFeed {
                return true
            }
            if !nextTouches, last == carriageReturn, after == lineFeed {
                return true
            }
        }
        return false
    }

    /// Rearranges the block `[startLine...endLine]` and the single adjacent
    /// line (above for `moveUp`, below otherwise) via one pure content
    /// swap over their exact combined span — the same set of lines, in a
    /// new order, replacing the identical span they already occupied.
    ///
    /// Every terminator inside the span is preserved VERBATIM, never
    /// assumed to be `"\n"` — a P1 an independent hostile review found: the
    /// original implementation rejoined bare line content with a literal
    /// `"\n"`, silently downgrading a CRLF or bare-CR document's own line
    /// endings to LF within the swapped span. The block's own INTERNAL
    /// terminators (between its own lines, if it spans more than one) never
    /// change position and are copied through unchanged; only the ONE
    /// terminator that sits between the block and the adjacent line
    /// relocates to the opposite side, but its own exact text is preserved.
    private static func swapReplacement(
        startLine: Int,
        endLine: Int,
        moveUp: Bool,
        lineIndex: EditorLineIndex,
        text: NSString
    ) -> (replacement: TextReplacement, blockOffsetInNewContent: Int) {
        let adjacentLine = moveUp ? startLine - 1 : endLine + 1
        let spanStartLine = moveUp ? adjacentLine : startLine
        let spanEndLine = moveUp ? endLine : adjacentLine

        let spanStart = lineIndex.utf16Range(ofLine: spanStartLine, in: text).location
        let spanEndLineRange = lineIndex.utf16Range(ofLine: spanEndLine, in: text)
        let spanEnd = spanEndLineRange.location + spanEndLineRange.length
        let combinedRange = NSRange(location: spanStart, length: spanEnd - spanStart)

        let blockLines = (startLine ... endLine)
            .map { text.substring(with: lineIndex.utf16Range(ofLine: $0, in: text)) }
        let blockInternalTerminators = (startLine ..< endLine)
            .map { EditorLineTransforms.terminatorText(afterLine: $0, lineIndex: lineIndex, text: text) }
        let adjacentContent = text.substring(with: lineIndex.utf16Range(ofLine: adjacentLine, in: text))
        let adjacentTerminatorLine = moveUp ? adjacentLine : endLine
        let adjacentTerminator = EditorLineTransforms.terminatorText(
            afterLine: adjacentTerminatorLine,
            lineIndex: lineIndex,
            text: text
        )

        var blockJoined = ""
        for (index, line) in blockLines.enumerated() {
            blockJoined += line
            if index < blockInternalTerminators.count {
                blockJoined += blockInternalTerminators[index]
            }
        }

        let newContent = moveUp
            ? blockJoined + adjacentTerminator + adjacentContent
            : adjacentContent + adjacentTerminator + blockJoined
        let replacement = TextReplacement(range: combinedRange, replacementText: newContent)

        let blockOffsetInNewContent = moveUp
            ? 0
            : (adjacentContent as NSString).length + (adjacentTerminator as NSString).length
        return (replacement, blockOffsetInNewContent)
    }
}
