@testable import EditorCore
import Foundation
import Testing

/// Shared helpers for driving the pure engine and applying outcomes to a
/// UTF-16 string snapshot.
enum EditingAssistTestSupport {
    static func outcome(
        for action: EditingAssistAction,
        in text: String,
        selection: NSRange,
        configuration: EditingAssistConfiguration = .markdownDefault,
        profile: LanguageEditingProfile = .plainText
    ) -> EditingAssistOutcome {
        MarkdownEditingAssistEngine.outcome(
            for: action,
            text: text as NSString,
            selection: selection,
            configuration: configuration,
            profile: profile
        )
    }

    static func type(
        _ character: Character,
        in text: String,
        at location: Int,
        configuration: EditingAssistConfiguration = .markdownDefault,
        profile: LanguageEditingProfile = .plainText
    ) -> EditingAssistOutcome {
        outcome(
            for: .replacement(range: NSRange(location: location, length: 0), string: String(character)),
            in: text,
            selection: NSRange(location: location, length: 0),
            configuration: configuration,
            profile: profile
        )
    }

    /// Applies an `.edit` outcome and returns the resulting text and
    /// selection. Returns `nil` for non-edit outcomes.
    static func applied(_ outcome: EditingAssistOutcome, to text: String) -> (text: String, selection: NSRange)? {
        guard case let .edit(edit) = outcome else { return nil }
        let nsText = text as NSString
        let replaced = nsText.replacingCharacters(in: edit.replacementRange, with: edit.replacementString)
        return (replaced, edit.resultingSelection)
    }
}

@Suite("Editing assists — structural pairing")
struct EditingAssistPairingTests {
    private let support = EditingAssistTestSupport.self

    @Test("every structural opener pairs at a valid boundary")
    func openersPairAtBoundary() {
        let pairs: [(Character, String)] = [
            ("(", "()"),
            ("[", "[]"),
            ("{", "{}"),
            ("<", "<>"),
            ("\u{FF08}", "\u{FF08}\u{FF09}"),
            ("\u{300C}", "\u{300C}\u{300D}"),
            ("\u{300E}", "\u{300E}\u{300F}"),
            ("\u{2018}", "\u{2018}\u{2019}"),
            ("\u{201C}", "\u{201C}\u{201D}"),
            ("\u{2039}", "\u{2039}\u{203A}"),
            ("\u{00AB}", "\u{00AB}\u{00BB}"),
            ("\u{3008}", "\u{3008}\u{3009}"),
            ("\u{300A}", "\u{300A}\u{300B}"),
        ]
        for (opener, pair) in pairs {
            let outcome = support.type(opener, in: "foo bar", at: 3)
            let result = support.applied(outcome, to: "foo bar")
            #expect(result?.text == "foo" + pair + " bar", "opener \(opener)")
            #expect(result?.selection == NSRange(location: 4, length: 0), "opener \(opener)")
        }
    }

    @Test("opener before ordinary alphanumeric next character does not pair")
    func openerBeforeWordDoesNotPair() {
        let outcome = support.type("(", in: "foobar", at: 3)
        #expect(outcome == .passthrough)
    }

    @Test("symmetric quotes require a previous boundary")
    func symmetricQuoteRequiresPreviousBoundary() {
        // Inside a word: plain apostrophe, no pair.
        let inWord = support.type("'", in: "it's", at: 4)
        #expect(inWord == .passthrough)
        // At a boundary: pairs.
        let atBoundary = support.type("'", in: " foo", at: 0)
        let result = support.applied(atBoundary, to: " foo")
        #expect(result?.text == "'' foo")
        #expect(result?.selection == NSRange(location: 1, length: 0))
        // Double quote behaves the same.
        let double = support.type("\"", in: "it's", at: 4)
        #expect(double == .passthrough)
    }

    @Test("closer before identical existing closer moves selection without duplicate")
    func typeOverCloserMovesSelection() {
        let outcome = support.type(")", in: "foo()", at: 4)
        #expect(outcome == .selection(NSRange(location: 5, length: 0)))
        let bracket = support.type("]", in: "foo[]", at: 4)
        #expect(bracket == .selection(NSRange(location: 5, length: 0)))
    }

    @Test("selected content wraps for each structural opener")
    func selectionWrapsForOpeners() {
        let outcome = support.outcome(
            for: .replacement(range: NSRange(location: 0, length: 3), string: "("),
            in: "foo",
            selection: NSRange(location: 0, length: 3)
        )
        let result = support.applied(outcome, to: "foo")
        #expect(result?.text == "(foo)")
        #expect(result?.selection == NSRange(location: 1, length: 3))
    }

    @Test("paired Backspace deletes both characters once")
    func pairedBackspaceDeletesPair() {
        let outcome = support.outcome(
            for: .deleteBackward,
            in: "foo()",
            selection: NSRange(location: 4, length: 0)
        )
        let result = support.applied(outcome, to: "foo()")
        #expect(result?.text == "foo")
        #expect(result?.selection == NSRange(location: 3, length: 0))
    }

    @Test("ordinary Backspace passes through")
    func ordinaryBackspacePassesThrough() {
        let outcome = support.outcome(
            for: .deleteBackward,
            in: "foo",
            selection: NSRange(location: 3, length: 0)
        )
        #expect(outcome == .passthrough)
    }

    @Test("emoji and CJK neighbors prove UTF-16 and scalar-boundary correctness")
    func emojiAndCJKNeighbors() {
        // 🚀 is two UTF-16 units; the pair insert must land after both.
        let rocket = support.type("(", in: "\u{1F680}", at: 2)
        let rocketResult = support.applied(rocket, to: "\u{1F680}")
        #expect(rocketResult?.text == "\u{1F680}()")
        #expect(rocketResult?.selection == NSRange(location: 3, length: 0))

        let cjk = support.type("(", in: "\u{65E5}\u{672C}\u{8A9E}", at: 3)
        let cjkResult = support.applied(cjk, to: "\u{65E5}\u{672C}\u{8A9E}")
        #expect(cjkResult?.text == "\u{65E5}\u{672C}\u{8A9E}()")
        #expect(cjkResult?.selection == NSRange(location: 4, length: 0))

        // Emoji is ordinary non-boundary text: typing an opener right after
        // an emoji still pairs when the NEXT character is a boundary.
        let afterEmoji = support.type("(", in: "\u{1F680} ", at: 2)
        let afterEmojiResult = support.applied(afterEmoji, to: "\u{1F680} ")
        #expect(afterEmojiResult?.text == "\u{1F680}() ")
    }

    @Test("paired Backspace around emoji text does not misclassify")
    func backspaceWithEmojiNeighbor() {
        // "🚀(|)" — the ASCII pair still deletes as one edit around an emoji.
        let outcome = support.outcome(
            for: .deleteBackward,
            in: "\u{1F680}()",
            selection: NSRange(location: 3, length: 0)
        )
        let result = support.applied(outcome, to: "\u{1F680}()")
        #expect(result?.text == "\u{1F680}")
        #expect(result?.selection == NSRange(location: 2, length: 0))
    }
}

@Suite("Editing assists — Markdown delimiter pairing")
struct EditingAssistMarkdownDelimiterTests {
    private let support = EditingAssistTestSupport.self

    @Test("* in prose boundary inserts an empty pair")
    func starPairsInProse() {
        let outcome = support.type("*", in: "foo bar", at: 3)
        let result = support.applied(outcome, to: "foo bar")
        #expect(result?.text == "foo** bar")
        #expect(result?.selection == NSRange(location: 4, length: 0))
    }

    @Test("* at first non-whitespace line position does not pair")
    func starDoesNotPairAtLineStart() {
        let outcome = support.type("*", in: "foo", at: 0)
        #expect(outcome == .passthrough)
        let indented = support.type("*", in: "  foo", at: 2)
        #expect(indented == .passthrough)
    }

    @Test("second * inside *|* completes the strong opener")
    func secondStarUpgradesToStrong() {
        // The `*|*` shape plus a second `*` re-inserts the pair (identity
        // text) and moves the caret one unit right — the strong opener
        // `**` with the caret after it, ready for content.
        let outcome = support.type("*", in: "**", at: 1)
        #expect(outcome == .selection(NSRange(location: 2, length: 0)))
    }

    @Test("strong emphasis can be typed naturally end to end")
    func strongEmphasisTypingFlow() {
        var text = ""
        var selection = NSRange(location: 0, length: 0)
        for character in "**foo**" {
            let outcome = support.type(character, in: text, at: selection.location)
            switch outcome {
            case .passthrough:
                // Native insertion: the character lands at the caret.
                text = (text as NSString).replacingCharacters(
                    in: NSRange(location: selection.location, length: 0),
                    with: String(character)
                )
                selection = NSRange(location: selection.location + 1, length: 0)
            case let .edit(edit):
                text = (text as NSString).replacingCharacters(in: edit.replacementRange, with: edit.replacementString)
                selection = edit.resultingSelection
            case let .selection(range):
                selection = range
            case .handledNoChange:
                break
            }
        }
        #expect(text == "**foo**")
        #expect(selection == NSRange(location: 7, length: 0))
    }

    @Test("_ pairs only at a boundary")
    func underscorePairsAtBoundaryOnly() {
        let atStart = support.type("_", in: " foo", at: 0)
        let atStartResult = support.applied(atStart, to: " foo")
        #expect(atStartResult?.text == "__ foo")
        #expect(atStartResult?.selection == NSRange(location: 1, length: 0))

        let endOfLine = support.type("_", in: "foo", at: 3)
        #expect(endOfLine == .passthrough)

        // Intra-word underscore never auto-pairs.
        let inWord = support.type("_", in: "foobar", at: 3)
        #expect(inWord == .passthrough)
    }

    @Test("second _ upgrades to strong equivalent")
    func secondUnderscoreUpgrades() {
        let outcome = support.type("_", in: "__", at: 1)
        #expect(outcome == .selection(NSRange(location: 2, length: 0)))
    }

    @Test("backtick pairs and has no fence escalation")
    func backtickPairs() {
        let outcome = support.type("`", in: "foo", at: 3)
        let result = support.applied(outcome, to: "foo")
        #expect(result?.text == "foo``")
        #expect(result?.selection == NSRange(location: 4, length: 0))
    }

    @Test("type-over works for symmetric closing delimiters")
    func typeOverSymmetricDelimiters() {
        let star = support.type("*", in: "**foo**", at: 5)
        #expect(star == .selection(NSRange(location: 6, length: 0)))
        let backtick = support.type("`", in: "foo``", at: 4)
        #expect(backtick == .selection(NSRange(location: 5, length: 0)))
    }

    @Test("selection wrapping keeps logical content selected")
    func selectionWrapKeepsContentSelected() {
        let outcome = support.outcome(
            for: .replacement(range: NSRange(location: 0, length: 3), string: "*"),
            in: "foo",
            selection: NSRange(location: 0, length: 3)
        )
        let result = support.applied(outcome, to: "foo")
        #expect(result?.text == "*foo*")
        #expect(result?.selection == NSRange(location: 1, length: 3))
    }

    @Test("second wrapping of still-selected content produces strong delimiters")
    func secondWrapProducesStrong() {
        let first = support.outcome(
            for: .replacement(range: NSRange(location: 0, length: 3), string: "*"),
            in: "foo",
            selection: NSRange(location: 0, length: 3)
        )
        let firstResult = support.applied(first, to: "foo")
        let second = support.outcome(
            for: .replacement(range: NSRange(location: 1, length: 3), string: "*"),
            in: firstResult?.text ?? "",
            selection: NSRange(location: 1, length: 3)
        )
        let secondResult = support.applied(second, to: firstResult?.text ?? "")
        #expect(secondResult?.text == "**foo**")
        #expect(secondResult?.selection == NSRange(location: 2, length: 3))
    }

    @Test("= and ~ receive native pass-through behavior")
    func legacyEqualsAndTildePassThrough() {
        #expect(support.type("=", in: "foo", at: 3) == .passthrough)
        #expect(support.type("~", in: "foo", at: 3) == .passthrough)
    }

    @Test("completesMatchingCharacters only gates structural (bracket/quote) pair paths")
    func matchingCharacterFlagGatesOnlyStructuralPairs() {
        // EPIC-22 §6.11, Slice 4a split the once-bundled `completesMatchingCharacters`
        // flag into this general/structural flag and a separate
        // `completesMarkdownDelimiters` flag for `*`/`_`/backtick — see the
        // sibling test below for that half.
        var configuration = EditingAssistConfiguration.markdownDefault
        configuration.completesMatchingCharacters = false

        #expect(support.type("(", in: "foo", at: 3, configuration: configuration) == .passthrough)
        // Markdown symmetric-delimiter wrapping/backspace are UNAFFECTED by
        // this flag now — they still fire, since `completesMarkdownDelimiters`
        // defaults to `true` and this configuration never touches it.
        #expect(
            support.outcome(
                for: .replacement(range: NSRange(location: 1, length: 3), string: "*"),
                in: "foo",
                selection: NSRange(location: 1, length: 3),
                configuration: configuration
            ) != .passthrough
        )
        #expect(
            support.outcome(
                for: .deleteBackward,
                in: "foo**bar",
                selection: NSRange(location: 4, length: 0),
                configuration: configuration
            ) != .passthrough
        )
    }

    @Test("completesMarkdownDelimiters only gates symmetric (*/_/backtick) pair paths")
    func markdownDelimiterFlagGatesOnlySymmetricPairs() {
        var configuration = EditingAssistConfiguration.markdownDefault
        configuration.completesMarkdownDelimiters = false

        // Symmetric wrap/backspace now pass through.
        #expect(
            support.outcome(
                for: .replacement(range: NSRange(location: 1, length: 3), string: "*"),
                in: "foo",
                selection: NSRange(location: 1, length: 3),
                configuration: configuration
            ) == .passthrough
        )
        #expect(
            support.outcome(
                for: .deleteBackward,
                in: "foo**bar",
                selection: NSRange(location: 4, length: 0),
                configuration: configuration
            ) == .passthrough
        )
        // Structural (bracket) pairing is UNAFFECTED by this flag.
        #expect(support.type("(", in: "foo", at: 3, configuration: configuration) != .passthrough)
    }

    @Test("paired Backspace on Markdown pair behaves as documented")
    func pairedBackspaceOnMarkdownPair() {
        // `*|*`: one Backspace removes both.
        let single = support.outcome(
            for: .deleteBackward,
            in: "foo**bar",
            selection: NSRange(location: 4, length: 0)
        )
        let singleResult = support.applied(single, to: "foo**bar")
        #expect(singleResult?.text == "foobar")
        #expect(singleResult?.selection == NSRange(location: 3, length: 0))
    }

    @Test("**|** reduces one star pair at a time")
    func strongPairBackspaceReducesStepwise() {
        // "**|**" — one Backspace reduces to "*|*".
        let first = support.outcome(
            for: .deleteBackward,
            in: "foo****bar",
            selection: NSRange(location: 5, length: 0)
        )
        let firstResult = support.applied(first, to: "foo****bar")
        #expect(firstResult?.text == "foo**bar")
        #expect(firstResult?.selection == NSRange(location: 4, length: 0))

        // A second Backspace removes the remaining pair.
        let second = support.outcome(
            for: .deleteBackward,
            in: firstResult?.text ?? "",
            selection: firstResult?.selection ?? NSRange(location: 0, length: 0)
        )
        let secondResult = support.applied(second, to: firstResult?.text ?? "")
        #expect(secondResult?.text == "foobar")
        #expect(secondResult?.selection == NSRange(location: 3, length: 0))
    }
}
