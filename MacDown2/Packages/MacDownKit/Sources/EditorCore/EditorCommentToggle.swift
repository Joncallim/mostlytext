import Foundation

// MARK: - Toggle Comment (EPIC-22 §6.13, Slice 4c-iii)

/// Pure, synchronous logic for Toggle Comment — the last of Slice 4c's ten
/// built-in transforms. Reuses `EditorLineTransforms`' own line-block
/// merging (the same "two carets on the same/adjacent lines must not
/// produce overlapping replacements" concern every other multi-line
/// transform in this epic already solved) and `EditorLineTransforms.makeTransaction`.
///
/// "Smart toggle" semantics (VSCode/Sublime/Xcode's shared convention): if
/// every touched line already starts (after its own leading whitespace)
/// with the effective profile's `lineComment` prefix, remove it from every
/// line that has it; otherwise add it to every line that doesn't. A profile
/// with no `lineComment` (Markdown, HTML, XML, CSS in this codebase's own
/// registry — a REAL, common case, not a rare edge case) falls back to
/// wrapping the whole block once with `blockComment`'s `open`/`close`
/// instead. A profile with neither declines the WHOLE command (matching
/// this epic's established "the whole command disables rather than
/// silently half-applying" precedent for Sort/Dedupe/Indent) — a MIXED
/// selection where one merged group's own effective profile has comment
/// syntax and another's doesn't is treated the same way, not partially
/// applied.
enum EditorCommentToggle {
    static func toggleCommentTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet,
        isMarkdownFormat: Bool,
        profile: LanguageEditingProfile
    ) -> EditorEditTransaction? {
        let groups = EditorLineTransforms.mergedLineBlockGroups(for: selection, lineIndex: lineIndex)
        guard !groups.isEmpty else { return nil }

        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0

        for group in groups {
            let effectiveProfile = isMarkdownFormat
                ? fenceAwareProfile(forAnchorLine: group.startLine, text: text, lineIndex: lineIndex, fallback: profile)
                : profile
            guard let outcome = toggleOutcome(for: group, text: text, lineIndex: lineIndex, profile: effectiveProfile)
            else {
                return nil
            }

            replacements.append(TextReplacement(range: outcome.range, replacementText: outcome.newContent))
            for index in group.memberIndices {
                let original = selection.ranges[index]
                let shifted = outcome.remap(original)
                resultsByOriginalIndex[index] = NSRange(location: shifted.location + delta, length: shifted.length)
            }
            delta += (outcome.newContent as NSString).length - outcome.range.length
        }

        // Removing a comment marker can leave a `\r` directly before an unrelated `\n` (mixed endings), which would
        // be read back as one `\r\n`, dropping a line.
        guard !EditorLineTransforms.createsCRLFPair(replacements, in: text) else { return nil }

        return EditorLineTransforms.makeTransaction(
            replacements: replacements,
            resultsByOriginalIndex: resultsByOriginalIndex,
            selection: selection,
            undoActionName: String(localized: "Toggle Comment", bundle: .module)
        )
    }

    /// Resolves the profile Markdown's own comment-toggle should actually
    /// use at `anchorLine` — exactly the way `MarkdownEditingAssistEngine`'s
    /// `effectiveConfigurationAndProfile` already resolves it for ambient
    /// typing assists (§6.12): the fenced language's own profile when
    /// `anchorLine` is inside a fence (Markdown has no line-comment syntax
    /// of its own to toggle there), `.plainText` inside front matter,
    /// `fallback` (the document's own Markdown profile) in ordinary prose.
    /// A selection spanning both a fence and surrounding prose is scoped
    /// entirely to whichever profile ITS OWN anchor line resolves to — a
    /// mixed per-line profile within one selection would make the smart-
    /// toggle "already commented?" check itself ambiguous. A disclosed
    /// consequence an independent hostile review confirmed: a wide
    /// selection starting INSIDE a fence and reaching past that fence's own
    /// closing delimiter (and beyond, into surrounding prose) comments the
    /// closing "```" line itself with the fenced language's own line
    /// comment, corrupting it as a fence marker — accepted as a rare,
    /// disclosed edge case (this profile-resolution rule is what the
    /// design contract explicitly asks for) rather than a bug to special-
    /// case away; pinned by `fenceAwareProfileScopesAWideSelectionSpanningTheFenceBoundaryToItsOwnAnchorLine`.
    private static func fenceAwareProfile(
        forAnchorLine anchorLine: Int,
        text: NSString,
        lineIndex: EditorLineIndex,
        fallback: LanguageEditingProfile
    ) -> LanguageEditingProfile {
        let anchorOffset = lineIndex.lineStartOffsets[anchorLine - 1]
        switch FencedRegionClassifier.classify(text: text, atUTF16Offset: anchorOffset) {
        case .prose:
            return fallback
        case .frontMatter:
            return .plainText
        case let .fencedCode(languageID):
            return languageID.map { LanguageEditingProfileRegistry.profile(for: $0) } ?? .plainText
        }
    }

    /// One group's own toggle result: the replacement itself, plus a
    /// closure remapping any ORIGINAL absolute position within the group to
    /// its own final absolute position (before this group's own contribution
    /// to the cross-group cumulative `delta` other groups also need).
    private struct ToggleOutcome {
        let range: NSRange
        let newContent: String
        let remap: (NSRange) -> NSRange
    }

    private static func toggleOutcome(
        for group: EditorLineTransforms.LineBlockGroup,
        text: NSString,
        lineIndex: EditorLineIndex,
        profile: LanguageEditingProfile
    ) -> ToggleOutcome? {
        let groupStart = lineIndex.lineStartOffsets[group.startLine - 1]
        let endContentRange = lineIndex.utf16Range(ofLine: group.endLine, in: text)
        let groupRange = NSRange(
            location: groupStart,
            length: endContentRange.location + endContentRange.length - groupStart
        )
        let groupContent = text.substring(with: groupRange)

        if let lineComment = profile.lineComment {
            let (lines, separators) = EditorLineTransforms.logicalLines(of: groupContent)
            let result = lineCommentToggle(lines: lines, prefix: lineComment)
            let newContent = EditorLineTransforms.joinLogicalLines(result.lines, separators: separators)
            let lineLengths = lines.map { ($0 as NSString).length }
            let newLength = (newContent as NSString).length
            return ToggleOutcome(range: groupRange, newContent: newContent) { original in
                let remapped = remappedCommentToggleSelection(
                    original: NSRange(location: original.location - groupRange.location, length: original.length),
                    lineLengths: lineLengths,
                    insertionColumns: result.insertionColumns,
                    deltas: result.deltas,
                    newLength: newLength
                )
                return NSRange(location: groupRange.location + remapped.location, length: remapped.length)
            }
        }

        if let blockComment = profile.blockComment {
            let (newContent, shift) = blockCommentToggle(
                groupContent,
                open: blockComment.open,
                close: blockComment.close
            )
            return ToggleOutcome(range: groupRange, newContent: newContent) { original in
                NSRange(location: original.location + shift, length: original.length)
            }
        }

        return nil
    }

    /// Per-line smart toggle: if EVERY NON-BLANK line (after its own leading
    /// whitespace) already starts with `prefix`, strip it (plus one
    /// following space, if present) from each of them; otherwise add
    /// `prefix + " "` to every non-blank line that doesn't already have it.
    /// Blank/whitespace-only lines are entirely skipped in both directions
    /// (delta 0, content untouched) — an independent hostile review found a
    /// genuine P2 in an earlier version that folded blank lines into the
    /// "already commented?" decision: a block where every REAL line was
    /// already commented except one blank line wrongly registered as "not
    /// all commented," so pressing the shortcut on a block that visibly
    /// looked fully commented added a second, redundant prefix to every
    /// already-commented line instead of stripping them.
    ///
    /// Also returns `insertionColumns`, the UTF-16 column (== character
    /// count, since leading whitespace is pure ASCII space/tab) at which
    /// each line's own edit actually happens — needed because that point is
    /// AFTER the line's own leading whitespace, not column 0 the way
    /// Indent's own per-line edit is. A P1 an independent hostile review
    /// found: reusing `MarkdownEditingAssistEngine.remappedSelection`
    /// directly (which only special-cases "at column 0, unaffected") wrongly
    /// applied a whole line's own full delta to any caret sitting strictly
    /// INSIDE that line's own leading whitespace, teleporting it past the
    /// just-inserted/removed prefix instead of leaving it exactly where it
    /// was. `remappedCommentToggleSelection` below is this transform's own
    /// remap, aware of the real per-line insertion column.
    /// The result of `lineCommentToggle`: the rewritten lines, each one's
    /// own UTF-16 length delta, and each one's own insertion column.
    private struct LineCommentToggleResult {
        let lines: [String]
        let deltas: [Int]
        let insertionColumns: [Int]
    }

    private static func lineCommentToggle(lines: [String], prefix: String) -> LineCommentToggleResult {
        func leadingWhitespace(of line: String) -> Substring {
            line.prefix { $0 == " " || $0 == "\t" }
        }
        func isBlank(_ line: String) -> Bool {
            // A CRLF document's lines keep their trailing "\r" after the "\n" split,
            // which must not make an otherwise-blank line look non-blank.
            let body = line.hasSuffix("\r") ? String(line.dropLast()) : line
            return leadingWhitespace(of: body).count == body.count
        }
        let allCommented = lines.allSatisfy { line in
            isBlank(line)
                || line.dropFirst(leadingWhitespace(of: line).count).unicodeScalars.starts(with: prefix.unicodeScalars)
        }

        var deltas: [Int] = []
        var insertionColumns: [Int] = []
        let processed = lines.map { line -> String in
            let leading = leadingWhitespace(of: line)
            insertionColumns.append(leading.count)
            let rest = line.dropFirst(leading.count)

            guard !isBlank(line) else {
                deltas.append(0)
                return line
            }
            if allCommented {
                // Scalar view: the space inserted by the comment command merges with a following U+0301/ZWJ/VS16 into
                // one `Character`, which a Character-level `first == " "` never matched, leaving a stray space on
                // every comment/uncomment cycle.
                var afterPrefix = rest.unicodeScalars.dropFirst(prefix.unicodeScalars.count)
                var removedLength = (prefix as NSString).length
                if afterPrefix.first == " " {
                    afterPrefix = afterPrefix.dropFirst()
                    removedLength += 1
                }
                deltas.append(-removedLength)
                return String(leading) + String(afterPrefix)
            }
            guard !rest.unicodeScalars.starts(with: prefix.unicodeScalars) else {
                deltas.append(0)
                return line
            }
            let inserted = prefix + " "
            deltas.append((inserted as NSString).length)
            return String(leading) + inserted + rest
        }
        return LineCommentToggleResult(lines: processed, deltas: deltas, insertionColumns: insertionColumns)
    }

    /// Maps a position within the ORIGINAL block (already relative to the
    /// block's own start) to its final position after `lineCommentToggle`'s
    /// own per-line edits — a position AT OR BEFORE a line's own
    /// `insertionColumns[index]` (its leading-whitespace length, where the
    /// edit itself happens) is unaffected by THAT line's own delta, since
    /// it sits strictly before the edit point; a position strictly AFTER
    /// the edit shifts by the line's own delta; a position that fell
    /// STRICTLY INSIDE a just-removed prefix (uncommenting only — `delta <
    /// 0`) has nothing left to sit on and clamps to the insertion point
    /// itself, rather than applying the removal's full negative delta and
    /// landing somewhere BEFORE the line's own leading whitespace (a P2 an
    /// independent hostile review found: a caret between the two `/`
    /// characters of `//` at the moment of uncommenting used to jump to
    /// before the leading whitespace instead of to where the removed
    /// prefix used to start). This generalizes
    /// `MarkdownEditingAssistEngine.remappedLocation`'s own "at column 0,
    /// unaffected" special case (correct for Indent's own column-0 edits,
    /// and correct for indent/outdent since a partial-indent removal can
    /// never leave a caret past where non-whitespace content starts) to an
    /// edit at an arbitrary per-line column, where that assumption no
    /// longer holds.
    private static func remappedCommentTogglePosition(
        _ position: Int,
        lineLengths: [Int],
        insertionColumns: [Int],
        deltas: [Int]
    ) -> Int {
        var shift = 0
        var lineStart = 0
        for (index, length) in lineLengths.enumerated() {
            let lineEnd = lineStart + length
            if position < lineStart {
                break
            }
            if position <= lineEnd {
                let column = position - lineStart
                let insertionColumn = insertionColumns[index]
                guard column > insertionColumn else { return position + shift }
                let delta = deltas[index]
                if delta < 0, column < insertionColumn - delta {
                    return lineStart + insertionColumn + shift
                }
                return position + shift + delta
            }
            shift += deltas[index]
            lineStart = lineEnd + 1
        }
        return position + shift
    }

    private static func remappedCommentToggleSelection(
        original: NSRange,
        lineLengths: [Int],
        insertionColumns: [Int],
        deltas: [Int],
        newLength: Int
    ) -> NSRange {
        let location = remappedCommentTogglePosition(
            original.location,
            lineLengths: lineLengths,
            insertionColumns: insertionColumns,
            deltas: deltas
        )
        let end = remappedCommentTogglePosition(
            original.location + original.length,
            lineLengths: lineLengths,
            insertionColumns: insertionColumns,
            deltas: deltas
        )
        let clampedLocation = min(max(0, location), newLength)
        let clampedEnd = min(max(0, end), newLength)
        return NSRange(location: clampedLocation, length: max(0, clampedEnd - clampedLocation))
    }

    /// Whole-block toggle for a `lineComment`-less profile: if `content`
    /// already starts with `open` and ends with `close`, strip them;
    /// otherwise wrap. `shift` is how much every position AT OR AFTER the
    /// block's own start moves by (positive when wrapping, negative when
    /// stripping) — a fixed amount, since this is a single insertion/
    /// deletion at the block's own start, unlike the per-line case.
    private static func blockCommentToggle(_ content: String, open: String,
                                           close: String) -> (content: String, shift: Int) {
        let openLength = (open as NSString).length
        let closeLength = (close as NSString).length
        if content.hasPrefix(open), content.hasSuffix(close),
           (content as NSString).length >= openLength + closeLength {
            let contentNSString = content as NSString
            let inner = contentNSString.substring(
                with: NSRange(location: openLength, length: contentNSString.length - openLength - closeLength)
            )
            return (inner, -openLength)
        }
        return (open + content + close, openLength)
    }
}
