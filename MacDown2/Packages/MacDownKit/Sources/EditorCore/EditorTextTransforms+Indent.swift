import Foundation

// MARK: - Increase/Decrease Indent (EPIC-22 §6.13, Slice 4c-ii)

extension EditorTextTransforms {
    /// Generalizes Tab/Shift-Tab's existing single-selection-only per-line
    /// indent engine (`MarkdownEditingAssistEngine.indentSelectedLines`/
    /// `unindentSelectedLines` — §6.13's own baseline note: this is NOT a
    /// from-scratch algorithm) to every active selection at once, as a
    /// dedicated, always-multi-selection-aware command distinct from the
    /// Tab key itself — Tab/Shift-Tab's own single-selection-only E10 assist
    /// scope (§7.2) is completely untouched by this.
    ///
    /// Reimplements the per-line transform inline (duplicating those two
    /// functions' own tiny closures, rather than calling them) rather than
    /// widening their access, because of a P1 an independent hostile review
    /// found in this method's first version: calling `indentSelectedLines`/
    /// `unindentSelectedLines` with a REPRESENTATIVE range covering the
    /// group's WHOLE line-block (needed so the text edit itself is correct)
    /// also made THEM compute `resultingSelection` for that same whole
    /// block — so even the single-caret, single-line common case installed
    /// a full-line SELECTION instead of leaving a collapsed caret, meaning
    /// the very next keystroke after ⌘]/⌘[ would replace the entire
    /// (re-)indented line. Computing this method's OWN per-line deltas
    /// (identical logic, `indentedLines`/`unindentedLines` below) instead
    /// makes `MarkdownEditingAssistEngine.remappedSelection` — already
    /// internal, the same primitive `transformSelectedLines` itself uses —
    /// directly callable on each GROUP MEMBER's own original position,
    /// which is what actually produces a correct per-member result.
    ///
    /// Line-block merging (`EditorLineTransforms.mergedLineBlockGroups`) is
    /// required for the same reason Sort/Dedupe need it: two carets on the
    /// same or adjacent lines would otherwise each independently expand to
    /// the SAME touched line(s), producing two overlapping (invalid)
    /// replacements. A DISCLOSED simplification for the resulting rare
    /// multi-member-per-group case: every member of a merged group is
    /// remapped independently and correctly (each keeps its own column),
    /// but if two members' own remapped positions happen to coincide (e.g.
    /// two bare carets on the exact same line), `EditorSelectionSet`'s own
    /// duplicate-caret merge rule collapses them to one — matching every
    /// other multi-cursor command's established convergence behavior in
    /// this codebase, not a defect specific to this one.
    static func indentTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet,
        width: Int,
        decrease: Bool,
        usesTabs: Bool = false
    ) -> EditorEditTransaction? {
        let groups = EditorLineTransforms.mergedLineBlockGroups(for: selection, lineIndex: lineIndex)
        guard !groups.isEmpty else { return nil }

        let context = IndentContext(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: width,
            decrease: decrease,
            unit: usesTabs ? "\t" : String(repeating: " ", count: width)
        )
        let accumulator = IndentAccumulator()
        for group in groups {
            applyIndent(to: group, context: context, into: accumulator)
        }

        guard !accumulator.replacements.isEmpty else { return nil }
        // Decrease Indent removing the blanks between a lone `\r` and the next `\n` would fuse them.
        guard !EditorLineTransforms.createsCRLFPair(accumulator.replacements, in: text) else { return nil }
        return EditorLineTransforms.makeTransaction(
            replacements: accumulator.replacements,
            resultsByOriginalIndex: accumulator.resultsByOriginalIndex,
            selection: selection,
            undoActionName: decrease ? String(localized: "Decrease Indent", bundle: .module) : String(
                localized: "Increase Indent",
                bundle: .module
            )
        )
    }

    /// Bundles this transform's own read-only inputs — kept below function-
    /// parameter-count limits without an `inout` accumulator's own moving
    /// parts mixed in.
    private struct IndentContext {
        let text: NSString
        let lineIndex: EditorLineIndex
        let selection: EditorSelectionSet
        let width: Int
        let decrease: Bool
        /// What one Increase Indent step inserts: spaces, or a tab when "Insert spaces for Tab" is off.
        let unit: String
    }

    /// A reference type (not a struct + `inout`) purely to keep
    /// `applyIndent`'s own parameter count within swiftlint's limit while
    /// still mutating shared state across every group in one pass.
    private final class IndentAccumulator {
        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0
    }

    /// Processes one merged group: computes its own indented/unindented
    /// content, appends a replacement (unless it would be a genuine no-op),
    /// and remaps every member's own original position through this
    /// group's own per-line deltas — extracted from `indentTransaction`
    /// itself to stay under swiftlint's function-body-length limit.
    private static func applyIndent(
        to group: EditorLineTransforms.LineBlockGroup,
        context: IndentContext,
        into accumulator: IndentAccumulator
    ) {
        let lineIndex = context.lineIndex
        let text = context.text
        let groupStart = lineIndex.lineStartOffsets[group.startLine - 1]
        let endContentRange = lineIndex.utf16Range(ofLine: group.endLine, in: text)
        let groupRange = NSRange(
            location: groupStart,
            length: endContentRange.location + endContentRange.length - groupStart
        )
        let groupContent = text.substring(with: groupRange)
        // Matches `transformSelectedLines`' own LF-only splitting convention
        // (pre-existing Tab/Shift-Tab behavior, not something this new
        // command changes) -- `groupRange` never includes a trailing
        // terminator (built the same way Join Lines' own content-only range
        // is), so there is no synthetic-trailing-empty-line case to handle
        // here, unlike that shared helper's own more general single-
        // selection-range input.
        let (realLines, separators) = EditorLineTransforms.logicalLines(of: groupContent)
        let (newLines, lineDeltas) = context.decrease
            ? unindentedLines(realLines, width: context.width)
            : indentedLines(realLines, unit: context.unit)
        let newContent = EditorLineTransforms.joinLogicalLines(newLines, separators: separators)

        guard newContent != groupContent else {
            // A genuine no-op for this group (e.g. Decrease Indent on
            // already-flush lines) -- every member keeps its own original
            // position, shifted only by earlier groups' own deltas, rather
            // than registering a wasted "replace X with X" edit.
            for index in group.memberIndices {
                let original = context.selection.ranges[index]
                accumulator.resultsByOriginalIndex[index] = NSRange(
                    location: original.location + accumulator.delta,
                    length: original.length
                )
            }
            return
        }

        accumulator.replacements.append(TextReplacement(range: groupRange, replacementText: newContent))

        let lineLengths = realLines.map { ($0 as NSString).length }
        let newLength = (newContent as NSString).length
        for index in group.memberIndices {
            let original = context.selection.ranges[index]
            let remapped = MarkdownEditingAssistEngine.remappedSelection(
                original: original,
                rangeLocation: groupRange.location,
                lineLengths: lineLengths,
                deltas: lineDeltas,
                newLength: newLength
            )
            // `remappedSelection` returns a position RELATIVE to
            // `rangeLocation` (confirmed by direct probe against the real,
            // already-shipped `MarkdownEditingAssistEngine.outcome` path: a
            // selection starting at a non-zero offset produces a
            // `resultingSelection` that is NOT a valid absolute document
            // position on its own) -- `groupRange.location` must be added
            // back explicitly before this group's own cumulative `delta`.
            accumulator.resultsByOriginalIndex[index] = NSRange(
                location: groupRange.location + remapped.location + accumulator.delta,
                length: remapped.length
            )
        }

        accumulator.delta += newLength - groupRange.length
    }

    /// Identical to `MarkdownEditingAssistEngine.indentSelectedLines`'s own
    /// per-line closure -- duplicated (see this file's own header comment
    /// for why) rather than shared.
    private static func indentedLines(_ lines: [String], unit: String) -> (lines: [String], deltas: [Int]) {
        (lines.map { unit + $0 }, lines.map { _ in unit.utf16.count })
    }

    /// Identical to `MarkdownEditingAssistEngine.unindentSelectedLines`'s
    /// own per-line closure -- duplicated (see this file's own header
    /// comment for why) rather than shared.
    private static func unindentedLines(_ lines: [String], width: Int) -> (lines: [String], deltas: [Int]) {
        var deltas: [Int] = []
        let processed = lines.map { line -> String in
            if line.hasPrefix("\t") {
                deltas.append(-1)
                return String(line.dropFirst())
            }
            let leadingSpaces = line.prefix { $0 == " " }.count
            let remove = min(leadingSpaces, width)
            deltas.append(-remove)
            return String(line.dropFirst(remove))
        }
        return (processed, deltas)
    }
}
