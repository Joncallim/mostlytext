@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §2.3, §6.12, §7.3 — Slice 4b: `MarkdownEditingAssistEngine`'s own
/// dispatch correctly substitutes a fence/front-matter-aware configuration
/// and profile, closing the E10 inherited-debt item. `FencedRegionClassifier`
/// itself has its own dedicated, exhaustive test suite
/// (`FencedRegionClassifierTests.swift`) — these tests are specifically
/// about the ENGINE's own behavior change once that classification is in
/// hand, not the classifier's own correctness.
@Suite("Editing assists — fenced-region gating (Slice 4b)")
struct EditingAssistFencedRegionTests {
    private let markdownProfile = LanguageEditingProfileRegistry.profile(for: "markdown")

    // MARK: - Symmetric Markdown delimiters do not fire inside a fence

    @Test("typing * inside a fenced code block does NOT trigger Markdown symmetric pairing")
    func asteriskInsideFenceDoesNotSymmetricPair() {
        let text = "prose\n```swift\nlet x = 1\n```\nmore" as NSString
        let caret = text.range(of: "let x").location

        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: caret, length: 0), string: "*"),
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: markdownProfile
        )

        #expect(outcome == .passthrough, "swift has no *-pairing in its own profile, and Markdown's own is suppressed")
    }

    @Test("typing * in ordinary prose (outside any fence) still symmetric-pairs as before")
    func asteriskInProseStillSymmetricPairs() {
        let text = "prose\n```swift\ncode\n```\nmore prose " as NSString
        // At the end after whitespace, this is an opening delimiter in
        // ordinary prose. A delimiter immediately after a word at line end
        // is covered separately as a possible emphasis closer.
        let caret = text.length

        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: caret, length: 0), string: "*"),
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: markdownProfile
        )

        guard case .edit = outcome else {
            Issue.record("expected symmetric pairing to fire in ordinary prose, got \(outcome)")
            return
        }
    }

    // MARK: - Structural pairing still uses the FENCE's own language profile

    @Test("typing ( inside a fenced code block still pairs (general, every profile's default)")
    func structuralPairingInsideFenceStillFires() {
        let text = "prose\n```swift\nlet x = 1\n```\nmore" as NSString
        let caret = text.range(of: "1").location + 1

        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: caret, length: 0), string: "("),
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: markdownProfile
        )

        guard case .edit = outcome else {
            Issue.record("expected structural bracket pairing (general, every profile's default) to still fire")
            return
        }
    }

    @Test("Return inside a fence uses the FENCED LANGUAGE's own indentAfterTrailing, not Markdown's (empty) one")
    func returnInsideFenceUsesTheFencedLanguagesOwnIndentAfterTrailing() {
        // Distinguishes "using the fence's own profile" from "using some
        // generic default": Markdown's own general profile has an EMPTY
        // `indentAfterTrailing`, while `swift`'s registered profile
        // includes "{" -- so this behavior can only fire if the fenced
        // language's own profile, not Markdown's, is actually in effect.
        var configuration = EditingAssistConfiguration.markdownDefault
        configuration.indentationWidth = 4
        let text = "prose\n```swift\nfunc f() {\n```" as NSString
        let caret = text.range(of: "{").location + 1

        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .insertNewline,
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: configuration,
            profile: markdownProfile
        )

        guard case let .edit(edit) = outcome else {
            Issue.record("expected the swift fence's own indentAfterTrailing to add one more indent level")
            return
        }
        #expect(edit.replacementString == "\n    ")
    }

    // MARK: - Return inside a fence: general indentation, not list continuation

    @Test("Return inside a fence maintains indentation instead of continuing a Markdown list")
    func returnInsideFenceMaintainsIndentationNotListContinuation() {
        let text = "- outer item\n```swift\n    let x = 1\n```" as NSString
        let caret = text.range(of: "let x = 1").location + "let x = 1".utf16.count

        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .insertNewline,
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: markdownProfile
        )

        guard case let .edit(edit) = outcome else {
            Issue.record("expected the general newline behavior to fire inside the fence")
            return
        }
        // Maintains the code line's own 4-space indentation; must NOT
        // contain any list-marker text (e.g. "- ") from the outer list.
        #expect(edit.replacementString == "\n    ")
    }

    @Test("Return in ordinary prose still continues a Markdown list as before")
    func returnInProseStillContinuesMarkdownList() {
        let text = "- item" as NSString
        let caret = text.length

        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .insertNewline,
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: markdownProfile
        )

        guard case let .edit(edit) = outcome else {
            Issue.record("expected Markdown list continuation to still fire in ordinary prose")
            return
        }
        #expect(edit.replacementString == "\n- ")
    }

    // MARK: - Front matter: general mechanics, not Markdown list/delimiter behavior

    @Test("Return inside front matter does not trigger Markdown list continuation")
    func returnInsideFrontMatterDoesNotContinueLists() {
        let text = "---\ntitle: Test\n- not a list marker, just YAML\n---\nbody" as NSString
        let caret = text.range(of: "just YAML").location + "just YAML".utf16.count

        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .insertNewline,
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: markdownProfile
        )

        // No indentation on this line, and general behavior (not list
        // continuation) applies -- a plain passthrough (no indentation to
        // carry, and no list marker inserted).
        #expect(outcome == .passthrough)
    }

    @Test("typing * inside front matter does not trigger Markdown symmetric pairing")
    func asteriskInsideFrontMatterDoesNotSymmetricPair() {
        let text = "---\ntitle: Test\n---\nbody" as NSString
        let caret = text.range(of: "Test").location + "Test".utf16.count

        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: caret, length: 0), string: "*"),
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: markdownProfile
        )

        #expect(outcome == .passthrough)
    }

    // MARK: - An untagged/unregistered fence language falls back to .plainText

    @Test("an untagged fence falls back to .plainText -- structural pairing still general, no symmetric delimiters")
    func untaggedFenceFallsBackToPlainText() {
        let text = "```\nsome text\n```" as NSString
        // Right after "some" (before the space): the next character is a
        // boundary (whitespace), which structural opener pairing requires.
        let caret = text.range(of: "some").location + "some".utf16.count

        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: caret, length: 0), string: "("),
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: markdownProfile
        )

        guard case .edit = outcome else {
            Issue.record("expected .plainText's own default structural pairing to still fire")
            return
        }
    }

    // MARK: - A non-Markdown document is entirely unaffected by fence classification

    @Test("a non-Markdown document's own configuration is never touched by fence classification")
    func nonMarkdownDocumentIsUnaffectedByFenceText() {
        // A Swift source file that happens to contain literal ``` text
        // (e.g. inside a doc comment) must not have ITS OWN configuration
        // altered -- fence classification only ever applies when
        // `isMarkdownFormat` is already true.
        let text = "/// ```\n/// example\n/// ```\nlet x = 1" as NSString
        // End of the string: the next character is nil (a boundary), which
        // structural opener pairing requires.
        let caret = text.length

        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: caret, length: 0), string: "("),
            text: text,
            selection: NSRange(location: caret, length: 0),
            configuration: .general,
            profile: LanguageEditingProfileRegistry.profile(for: "swift")
        )

        guard case .edit = outcome else {
            Issue.record("expected ordinary structural pairing for a non-Markdown document, unaffected by ``` text")
            return
        }
    }
}
