import Foundation

// MARK: - Typed replacement / paired Backspace

// Extracted from `MarkdownEditingAssistEngine.swift` to keep that enum's own
// body under its line-count limit, mirroring the established per-feature-file
// split precedent (`+Indentation.swift`, `+Newline.swift`, `+Commands.swift`).

extension MarkdownEditingAssistEngine {
    static func replacementOutcome(
        range: NSRange,
        string: String,
        text: NSString,
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile
    ) -> EditingAssistOutcome {
        guard configuration.completesMatchingCharacters || configuration.completesMarkdownDelimiters else {
            return .passthrough
        }
        guard string.utf16.count == 1 else { return .passthrough }
        guard let unit = string.utf16.first, let scalar = UnicodeScalar(unit) else {
            return .passthrough
        }
        let character = Character(scalar)

        if range.length > 0 {
            return wrapOutcome(
                character: character,
                selection: range,
                text: text,
                configuration: configuration,
                profile: profile
            )
        }
        return collapsedTypingOutcome(
            character: character,
            caret: range.location,
            text: text,
            configuration: configuration,
            profile: profile
        )
    }

    /// Wrapping a non-empty selection with a structural opener (general,
    /// every format, via the active profile's `pairedDelimiters`) or a
    /// symmetric Markdown delimiter (Markdown only). The logical content
    /// stays selected so a second same-delimiter wrap produces strong
    /// emphasis naturally.
    private static func wrapOutcome(
        character: Character,
        selection: NSRange,
        text: NSString,
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile
    ) -> EditingAssistOutcome {
        let content = text.substring(with: selection)
        let prefix: String
        let suffix: String
        if configuration.completesMatchingCharacters, let closer = structuralCloser(
            for: character,
            in: profile.pairedDelimiters
        ) {
            prefix = String(character)
            suffix = String(closer)
        } else if configuration.completesMarkdownDelimiters, character == "*" || character == "_" || character == "`" {
            prefix = String(character)
            suffix = String(character)
        } else {
            return .passthrough
        }
        return .edit(EditingAssistEdit(
            replacementRange: selection,
            replacementString: prefix + content + suffix,
            resultingSelection: NSRange(location: selection.location + prefix.utf16.count, length: selection.length),
            undoActionName: String(localized: "Insert", bundle: .module)
        ))
    }

    private static func collapsedTypingOutcome(
        character: Character,
        caret: Int,
        text: NSString,
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile
    ) -> EditingAssistOutcome {
        let next = scalar(at: caret, in: text)
        let previous = scalar(before: caret, in: text)

        // Type-over: the typed character is already the immediate next
        // delimiter character (structural closer or symmetric delimiter).
        // This also covers the `*|*` shape: replacing the two stars with the
        // same pair and moving the caret one unit right is an identity edit,
        // which is what lets strong emphasis be typed naturally and lets the
        // closing pair of `**…**` be typed with one keystroke per star.
        if let next, Character(next) == character,
           isTypeOverTarget(character, configuration: configuration, profile: profile) {
            return .selection(NSRange(location: caret + utf16Length(of: next), length: 0))
        }

        if configuration.completesMatchingCharacters, let closer = structuralCloser(
            for: character,
            in: profile.pairedDelimiters
        ) {
            return structuralPairOutcome(
                character: character,
                closer: closer,
                caret: caret,
                previous: previous,
                next: next
            )
        }
        guard configuration.completesMarkdownDelimiters else { return .passthrough }
        return symmetricDelimiterOutcome(character: character, caret: caret, previous: previous, next: next, text: text)
    }

    private static func isTypeOverTarget(
        _ character: Character,
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile
    ) -> Bool {
        if configuration.completesMatchingCharacters,
           profile.pairedDelimiters.contains(where: { $0.closer == character }) {
            return true
        }
        if configuration.completesMarkdownDelimiters, character == "*" || character == "_" || character == "`" {
            return true
        }
        return false
    }

    /// Structural pair completion (with the permissive legacy previous-
    /// character behavior), plus the symmetric-quote previous-boundary rule.
    private static func structuralPairOutcome(
        character: Character,
        closer: Character,
        caret: Int,
        previous: Unicode.Scalar?,
        next: Unicode.Scalar?
    ) -> EditingAssistOutcome {
        let nextIsBoundary = next.map(isBoundary) ?? true
        guard nextIsBoundary else { return .passthrough }
        if character == closer {
            // Symmetric quote: also require a previous boundary/end.
            let previousIsBoundary = previous.map(isBoundary) ?? true
            guard previousIsBoundary else { return .passthrough }
        }
        return pairInsertion(character: character, closer: closer, caret: caret)
    }

    /// Symmetric Markdown delimiter pairing (`*`, `_`, backtick).
    private static func symmetricDelimiterOutcome(
        character: Character,
        caret: Int,
        previous: Unicode.Scalar?,
        next: Unicode.Scalar?,
        text: NSString
    ) -> EditingAssistOutcome {
        let nextIsBoundary = next.map(isBoundary) ?? true
        let repeatsPrevious = previous.map { Character($0) == character } ?? false
        // A delimiter typed immediately after a word at the physical end of
        // a line may be closing existing emphasis. Pairing it would turn
        // `*word*` into `*word**` (or the underscore equivalent). Keep the
        // ordinary boundary and selection-wrapping rules below unchanged.
        let followsWord = previous.map { !isBoundary($0) } ?? false
        let endsLine = next == nil || next == "\r" || next == "\n"
        if character == "*" || character == "_", followsWord, endsLine {
            return .passthrough
        }
        switch character {
        case "*":
            // At the first non-whitespace position of a line, do not auto-pair
            // a single `*`, so `* ` unordered-list typing stays natural.
            // Likewise never pair after an existing `*`: the second star of a
            // line-start `**`/`***` opener must insert natively.
            guard !isAtFirstNonWhitespace(caret, in: text) else { return .passthrough }
            if repeatsPrevious {
                return .passthrough
            }
            guard nextIsBoundary else { return .passthrough }
            return pairInsertion(character: "*", closer: "*", caret: caret)
        case "_":
            return underscoreOutcome(
                caret: caret, repeatsPrevious: repeatsPrevious, previous: previous, nextIsBoundary: nextIsBoundary
            )
        case "`":
            // Never pair after an existing backtick: typing ``` (a fence) would otherwise end as four
            // (the third keystroke pairs again), and ```swift as ```swift`.
            guard !repeatsPrevious, nextIsBoundary else { return .passthrough }
            return pairInsertion(character: "`", closer: "`", caret: caret)
        default:
            return .passthrough
        }
    }

    /// Pair only at a boundary; never auto-pair intra-word underscore, and never after an existing `_`
    /// (`___` must not grow a fourth).
    private static func underscoreOutcome(
        caret: Int,
        repeatsPrevious: Bool,
        previous: Unicode.Scalar?,
        nextIsBoundary: Bool
    ) -> EditingAssistOutcome {
        guard !repeatsPrevious else { return .passthrough }
        let previousBoundary = previous.map(isBoundary) ?? true
        guard previousBoundary || nextIsBoundary else { return .passthrough }
        return pairInsertion(character: "_", closer: "_", caret: caret)
    }

    private static func pairInsertion(character: Character, closer: Character, caret: Int) -> EditingAssistOutcome {
        let pair = String(character) + String(closer)
        return .edit(EditingAssistEdit(
            replacementRange: NSRange(location: caret, length: 0),
            replacementString: pair,
            resultingSelection: NSRange(location: caret + 1, length: 0),
            undoActionName: String(localized: "Insert", bundle: .module)
        ))
    }

    /// True when the caret is at the first non-whitespace position of its line.
    ///
    /// Scans backward from the caret so the common case (content immediately
    /// before the caret) exits after one unit instead of walking the whole
    /// line prefix, keeping the `*`-keypress decision local even at the end
    /// of a very long line.
    private static func isAtFirstNonWhitespace(_ caret: Int, in text: NSString) -> Bool {
        let start = lineStart(of: caret, in: text)
        var prefixEnd = start
        while prefixEnd < caret, isHorizontalWhitespace(character(at: prefixEnd, in: text)) {
            prefixEnd += 1
        }
        while prefixEnd < caret, character(at: prefixEnd, in: text) == 0x3E {
            prefixEnd += 1
            if prefixEnd < caret, character(at: prefixEnd, in: text) == 0x20 {
                prefixEnd += 1
            }
            while prefixEnd < caret, isHorizontalWhitespace(character(at: prefixEnd, in: text)) {
                prefixEnd += 1
            }
        }
        var index = caret
        while index > prefixEnd {
            let unit = character(at: index - 1, in: text)
            if unit != 0x20, unit != 0x09 {
                return false
            }
            index -= 1
        }
        return true
    }

    // MARK: - Paired Backspace

    static func backspaceOutcome(
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile
    ) -> EditingAssistOutcome {
        guard configuration.completesMatchingCharacters || configuration.completesMarkdownDelimiters else {
            return .passthrough
        }
        guard selection.length == 0 else { return .passthrough }
        let caret = selection.location
        guard caret > 0, caret < text.length else { return .passthrough }

        let previous = scalar(before: caret, in: text)
        let next = scalar(at: caret, in: text)
        guard let previous, let next else { return .passthrough }

        // Structural pair (general, every format).
        if configuration.completesMatchingCharacters,
           let opener = structuralOpener(for: Character(next), in: profile.pairedDelimiters),
           Character(previous) == opener {
            let range = NSRange(
                location: caret - utf16Length(of: previous),
                length: utf16Length(of: previous) + utf16Length(of: next)
            )
            return deletePair(range: range)
        }

        // Symmetric Markdown pair (`*|*`, `_|_`, `` `|` ``) — Markdown only.
        if configuration.completesMarkdownDelimiters {
            let previousCharacter = Character(previous)
            if previous == next, previousCharacter == "*" || previousCharacter == "_" || previousCharacter == "`" {
                return deletePair(range: NSRange(location: caret - 1, length: 2))
            }
        }

        return .passthrough
    }

    private static func deletePair(range: NSRange) -> EditingAssistOutcome {
        .edit(EditingAssistEdit(
            replacementRange: range,
            replacementString: "",
            resultingSelection: NSRange(location: range.location, length: 0),
            undoActionName: String(localized: "Delete", bundle: .module)
        ))
    }
}
