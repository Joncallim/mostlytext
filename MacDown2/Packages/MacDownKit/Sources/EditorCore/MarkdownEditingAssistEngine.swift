import Foundation

// MARK: - Internal action

/// The normalized input the adapter feeds into the pure engine.
enum EditingAssistAction: Equatable {
    /// A typed replacement (character or paste) at `range`.
    case replacement(range: NSRange, string: String)
    /// The Return key (`insertNewline:`).
    case insertNewline
    /// The Tab key (`insertTab:`).
    case insertTab
    /// Shift-Tab (`insertBacktab:`).
    case insertBacktab
    /// Backspace (`deleteBackward:`).
    case deleteBackward
    /// Smart Home (`moveToLeftEndOfLine:`).
    case smartHome
    /// A Markdown formatting menu command.
    case markdownCommand(MarkdownEditingCommand)
}

// MARK: - Line prefix model

/// A `[ ]` / `[x]` / `[X]` task marker. Continuation always emits `[ ]`.
enum TaskMarker: Equatable {
    case unchecked
    case checked
}

enum ListMarker: Equatable {
    case unordered(Character)
    case ordered(rawDigits: String)
}

/// The recognized Markdown line prefix before the caret:
/// `[indentation][zero or more > markers][list marker][task marker]`.
struct MarkdownLinePrefix: Equatable {
    let indentation: String
    let blockquotePrefix: String
    let listMarker: ListMarker?
    let taskMarker: TaskMarker?
    /// Range of the content between the recognized construct and the caret.
    let contentRangeInLine: NSRange
}

// MARK: - Engine

/// Pure, synchronous, UTF-16-local decision layer for E10 editing assists.
///
/// The engine never mutates `text`, never materializes a whole-document Swift
/// `String`, never runs Markdown parsing, and never allocates async work. All
/// offsets are UTF-16 (`NSRange`, `NSString.length`).
enum MarkdownEditingAssistEngine {
    /// The single entry point: decides the outcome for one input action.
    ///
    /// `profile` is the active document format's `LanguageEditingProfile`
    /// (EPIC-22 §6.11, Slice 4a) — required, not defaulted, so every call
    /// site states explicitly which profile is in effect rather than
    /// silently falling back to `.plainText`. It drives general, per-format
    /// mechanics (structural pairing, indent width, indent-after-trailing);
    /// Markdown's own symmetric-delimiter/list/heading behavior is
    /// unaffected by it and continues to key off `configuration`'s
    /// Markdown-specific flags alone.
    static func outcome(
        for action: EditingAssistAction,
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile
    ) -> EditingAssistOutcome {
        guard configuration.isEnabled else { return .passthrough }

        let clampedSelection = clampedRange(selection, length: text.length)
        let (effectiveConfiguration, effectiveProfile) = effectiveConfigurationAndProfile(
            configuration: configuration,
            profile: profile,
            text: text,
            caret: clampedSelection.location
        )
        return dispatchedOutcome(
            for: action,
            text: text,
            clampedSelection: clampedSelection,
            configuration: effectiveConfiguration,
            profile: effectiveProfile
        )
    }

    /// The per-action dispatch, extracted from `outcome(for:...)` itself to
    /// stay under swiftlint's function-body-length limit once the fence/
    /// front-matter substitution (§6.12) was added above it.
    private static func dispatchedOutcome(
        for action: EditingAssistAction,
        text: NSString,
        clampedSelection: NSRange,
        configuration effectiveConfiguration: EditingAssistConfiguration,
        profile effectiveProfile: LanguageEditingProfile
    ) -> EditingAssistOutcome {
        switch action {
        case let .replacement(range, string):
            replacementOutcome(
                range: clampedRange(range, length: text.length),
                string: string,
                text: text,
                configuration: effectiveConfiguration,
                profile: effectiveProfile
            )
        case .insertNewline:
            newlineOutcome(
                text: text,
                selection: clampedSelection,
                configuration: effectiveConfiguration,
                profile: effectiveProfile
            )
        case .insertTab:
            tabOutcome(
                text: text,
                selection: clampedSelection,
                configuration: effectiveConfiguration,
                profile: effectiveProfile,
                shift: false
            )
        case .insertBacktab:
            tabOutcome(
                text: text,
                selection: clampedSelection,
                configuration: effectiveConfiguration,
                profile: effectiveProfile,
                shift: true
            )
        case .deleteBackward:
            backspaceOutcome(
                text: text,
                selection: clampedSelection,
                configuration: effectiveConfiguration,
                profile: effectiveProfile
            )
        case .smartHome:
            smartHomeOutcome(text: text, selection: clampedSelection, configuration: effectiveConfiguration)
        case let .markdownCommand(command):
            // Deliberately NOT gated by fence classification in this slice
            // (§6.12, §7.3): an explicit, deliberate menu command (Bold,
            // Italic, Heading...) is a different interaction model from the
            // ambient typing/Return/Tab auto-assists this classifier exists
            // to gate.
            commandOutcome(command: command, text: text, selection: clampedSelection)
        }
    }

    /// Substitutes a fence/front-matter-aware configuration and profile for
    /// a Markdown document whose caret currently sits inside one (§6.12,
    /// §7.3, Slice 4b — the E10 inherited-debt item §2.3 named). A no-op
    /// (returns the inputs unchanged) for a non-Markdown document, or a
    /// Markdown document whose caret is in ordinary prose.
    private static func effectiveConfigurationAndProfile(
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile,
        text: NSString,
        caret: Int
    ) -> (EditingAssistConfiguration, LanguageEditingProfile) {
        guard configuration.isMarkdownFormat else { return (configuration, profile) }

        switch FencedRegionClassifier.classify(text: text, atUTF16Offset: caret) {
        case .prose:
            return (configuration, profile)
        case .frontMatter, .unresolved:
            return (nonMarkdownConfiguration(from: configuration), .plainText)
        case let .fencedCode(languageID):
            let fenceProfile = languageID.map { LanguageEditingProfileRegistry.profile(for: $0) } ?? .plainText
            return (nonMarkdownConfiguration(from: configuration), fenceProfile)
        }
    }

    /// `configuration` with every Markdown-specific behavior forced off and
    /// `isMarkdownFormat` forced `false` — general mechanics (structural
    /// pairing, Tab/Shift-Tab, Smart Home, generic Return-maintains-
    /// indentation) still run, driven by whichever profile the caller
    /// substitutes alongside this.
    private static func nonMarkdownConfiguration(
        from configuration: EditingAssistConfiguration
    ) -> EditingAssistConfiguration {
        var adjusted = configuration
        adjusted.isMarkdownFormat = false
        adjusted.continuesMarkdownPrefixes = false
        adjusted.completesMarkdownDelimiters = false
        adjusted.autoIncrementOrderedLists = false
        return adjusted
    }

    // MARK: - Smart Home

    private static func smartHomeOutcome(
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome {
        guard configuration.smartHome else { return .passthrough }
        let caret = selection.location
        let start = lineStart(of: caret, in: text)
        let contentEnd = lineContentEnd(of: caret, in: text)

        let nonWhitespace = firstNonWhitespace(in: text, from: start, to: contentEnd)
        let target: Int = if let nonWhitespace, caret != nonWhitespace {
            nonWhitespace
        } else {
            start
        }
        return .selection(NSRange(location: target, length: 0))
    }
}
