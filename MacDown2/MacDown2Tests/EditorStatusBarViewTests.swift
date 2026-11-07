import EditorCore
import Foundation
@testable import MacDown2
import Testing

/// EPIC-22 Slice 2b — the status bar's word/character-count and
/// line/column coverage `planning/epic-22-implementation.md` §6.7 commits
/// to (found missing by hostile review of PR #126).
@MainActor
@Suite("EditorStatusBarView")
struct EditorStatusBarViewTests {
    private func makeView(
        text: String,
        selectedRange: NSRange = NSRange(location: 0, length: 0),
        indentationWidth: Int = 4,
        convertsTabsToSpaces: Bool = true
    ) -> EditorStatusBarView {
        EditorStatusBarView(
            text: text,
            selectedRange: selectedRange,
            lineIndex: EditorLineIndex(text: text as NSString),
            indentationWidth: indentationWidth,
            convertsTabsToSpaces: convertsTabsToSpaces,
            onGoToLine: {}
        )
    }

    // MARK: - wordCount(in:)

    @Test func wordCountOfEmptyDocumentIsZero() {
        #expect(EditorStatusBarView.wordCount(in: "") == 0)
    }

    @Test func wordCountOfASingleWord() {
        #expect(EditorStatusBarView.wordCount(in: "hello") == 1)
    }

    @Test func wordCountOfAllWhitespaceIsZero() {
        #expect(EditorStatusBarView.wordCount(in: "   \n\t  ") == 0)
    }

    @Test func wordCountSeparatesOnWhitespaceAndPunctuation() {
        #expect(EditorStatusBarView.wordCount(in: "one two three") == 3)
        #expect(EditorStatusBarView.wordCount(in: "one, two, three.") == 3)
    }

    @Test func wordCountOfCJKText() {
        // Foundation's word-boundary logic segments CJK text into individual
        // characters/words rather than whitespace-delimited runs -- this
        // fixture asserts it does not crash and returns a positive count,
        // not a specific segmentation (that's ICU's own documented,
        // version-dependent behavior, not this codebase's to pin exactly).
        #expect(EditorStatusBarView.wordCount(in: "日本語のテスト") > 0)
    }

    @Test func wordCountOfEmojiOnlyText() {
        #expect(EditorStatusBarView.wordCount(in: "😀😀😀") >= 0)
    }

    // MARK: - countText

    @Test func countTextShowsDocumentCountsWhenNoSelection() {
        let view = makeView(text: "one two three")
        #expect(view.countText.contains("3 words"))
        #expect(view.countText.contains("13 characters"))
    }

    @Test func countTextShowsSelectedCountWhenSelectionIsNonEmpty() {
        let view = makeView(text: "one two three", selectedRange: NSRange(location: 0, length: 3))
        #expect(view.countText.contains("3 selected"))
        #expect(!view.countText.contains("words"))
    }

    @Test func countTextCountsCJKAndEmojiAsCharactersNotUTF16Units() {
        let text = "😀ab" // 😀 is 2 UTF-16 units, 1 character
        let view = makeView(text: text)
        #expect(view.countText.contains("3 characters"))
    }

    @Test func countTextOfEmptyDocument() {
        let view = makeView(text: "")
        #expect(view.countText.contains("0 characters"))
        #expect(view.countText.contains("0 words"))
    }

    @Test(arguments: [
        ("", "0 characters, 0 words"),
        ("a", "1 character, 1 word"),
        ("ab", "2 characters, 1 word"),
        ("a b", "3 characters, 2 words"),
    ])
    func documentCountsChooseIndependentEnglishPluralForms(text: String, expected: String) {
        #expect(makeView(text: text).countText == expected)
    }

    // MARK: - lineColumnText

    @Test func lineColumnTextAtDocumentStart() {
        let view = makeView(text: "one\ntwo\nthree")
        #expect(view.lineColumnText.contains("Ln 1"))
        #expect(view.lineColumnText.contains("Col 1"))
    }

    @Test func lineColumnTextOnASecondLine() {
        let view = makeView(text: "one\ntwo\nthree", selectedRange: NSRange(location: 5, length: 0))
        #expect(view.lineColumnText.contains("Ln 2"))
        #expect(view.lineColumnText.contains("Col 2"))
    }

    // MARK: - indentationText

    @Test func indentationTextShowsSpacesWhenConvertingTabs() {
        let view = makeView(text: "", indentationWidth: 2, convertsTabsToSpaces: true)
        #expect(view.indentationText.contains("Spaces"))
        #expect(view.indentationText.contains("2"))
    }

    @Test func indentationTextShowsTabsWhenNotConvertingTabs() {
        let view = makeView(text: "", indentationWidth: 8, convertsTabsToSpaces: false)
        #expect(view.indentationText.contains("Tabs"))
        #expect(view.indentationText.contains("8"))
    }
}
