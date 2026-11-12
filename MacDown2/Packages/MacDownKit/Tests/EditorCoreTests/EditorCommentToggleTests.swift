@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.13, Slice 4c-iii — pure-logic tests for Toggle Comment,
/// entirely independent of `NSTextView`.
@Suite("EditorCommentToggle (Slice 4c-iii)")
struct EditorCommentToggleTests {
    private let swiftProfile = LanguageEditingProfileRegistry.profile(for: "swift")
    private let markdownProfile = LanguageEditingProfileRegistry.profile(for: "markdown")
    private let plainTextProfile = LanguageEditingProfile.plainText
    private let texProfile = LanguageEditingProfileRegistry.profile(for: "tex")

    // MARK: - Line comment: add

    @Test("commenting adds the prefix to every line that doesn't already have it")
    func lineCommentAddsPrefix() {
        let text = "foo\nbar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "// foo\n// bar")
    }

    @Test("commenting skips a line that's already commented")
    func lineCommentSkipsAlreadyCommentedLine() {
        let text = "// foo\nbar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        // Not every line was already commented, so this is a "comment"
        // pass -- the already-commented line is left untouched, the other
        // gets the prefix added.
        #expect(applied?.text == "// foo\n// bar")
    }

    @Test("commenting preserves each line's own leading whitespace/indentation")
    func lineCommentPreservesIndentation() {
        let text = "  foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "  // foo")
    }

    // MARK: - Line comment: remove

    @Test("uncommenting strips the prefix and one following space when every line is already commented")
    func lineCommentRemovesPrefix() {
        let text = "// foo\n// bar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "foo\nbar")
    }

    @Test("uncommenting a prefix with no following space still strips just the prefix")
    func lineCommentRemovesPrefixWithoutFollowingSpace() {
        let text = "//foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "foo")
    }

    // MARK: - Multi-selection merge

    @Test("two carets on the same line merge into one group -- toggled exactly once, not twice")
    func lineCommentMergesTwoCaretsOnSameLine() {
        let text = "foobar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        #expect(transaction?.replacements.count == 1)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "// foobar")
    }

    // MARK: - No comment syntax at all

    @Test("a profile with neither lineComment nor blockComment declines entirely")
    func declinesWithNoCommentSyntax() {
        let text = "foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        // `.plainText` (and the registry's own "json" entry) has neither.
        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: plainTextProfile
        )
        #expect(transaction == nil)
    }

    // MARK: - Block comment fallback (lineComment == nil)

    @Test("a lineComment-less profile falls back to wrapping the whole block with blockComment")
    func blockCommentWrapsWholeBlock() {
        let text = "foo\nbar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        // Markdown's own registered profile has blockComment (HTML-style)
        // but no lineComment.
        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false, // exercising the profile directly, not fence resolution
            profile: markdownProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "<!--foo\nbar-->")
    }

    @Test("an already-wrapped block comment is stripped, not double-wrapped")
    func blockCommentStripsWhenAlreadyWrapped() {
        let text = "<!--foo\nbar-->" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: markdownProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "foo\nbar")
    }

    // MARK: - Fence-aware profile resolution for Markdown

    @Test("inside a fenced code block, Markdown's comment-toggle uses the FENCED LANGUAGE's own line comment")
    func fenceAwareProfileUsesFencedLanguage() {
        let text = "prose\n```swift\nlet x = 1\n```\nmore" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "let x").location
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: true,
            profile: markdownProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        // swift's own "//" line comment, not Markdown's HTML-style block
        // comment.
        #expect(applied?.text == "prose\n```swift\n// let x = 1\n```\nmore")
    }

    @Test("in ordinary Markdown prose, comment-toggle uses Markdown's own block comment")
    func fenceAwareProfileUsesMarkdownInProse() {
        let text = "prose\n```swift\ncode\n```\nmore text" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "more text").location
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: "more text".utf16.count))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: true,
            profile: markdownProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "prose\n```swift\ncode\n```\n<!--more text-->")
    }

    @Test("inside front matter, comment-toggle declines (plainText has no comment syntax)")
    func fenceAwareProfileDeclinesInsideFrontMatter() {
        let text = "---\ntitle: Test\n---\nbody" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "title:").location
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: true,
            profile: markdownProfile
        )
        #expect(transaction == nil)
    }

    // MARK: - TeX (Slice 9c)

    @Test("TeX profile comments with % and has no block comment")
    func texProfileUsesPercentLineComment() {
        #expect(texProfile.lineComment == "%")
        #expect(texProfile.blockComment == nil)

        let text = "\\section{A}\nbody" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))
        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: texProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "% \\section{A}\n% body")
    }
}
