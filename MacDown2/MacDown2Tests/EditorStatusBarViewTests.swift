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

    @Test(arguments: ["en", "fr", "ja", "pl"])
    func compiledDocumentCountsUseIndependentLocalePluralForms(_ language: String) throws {
        let url = try #require(Bundle.main.url(forResource: language, withExtension: "lproj"))
        let resources = try #require(Bundle(url: url))
        let pairs = [(0, 0), (1, 1), (2, 2), (5, 1), (12, 22), (22, 12)]
        let expected: [String] = switch language {
        case "en": [
                "0 characters, 0 words", "1 character, 1 word", "2 characters, 2 words",
                "5 characters, 1 word", "12 characters, 22 words", "22 characters, 12 words",
            ]
        case "fr": [
                "0 caractère, 0 mot", "1 caractère, 1 mot", "2 caractères, 2 mots",
                "5 caractères, 1 mot", "12 caractères, 22 mots", "22 caractères, 12 mots",
            ]
        case "ja": [
                "0文字、0語", "1文字、1語", "2文字、2語",
                "5文字、1語", "12文字、22語", "22文字、12語",
            ]
        case "pl": [
                "0 znaków, 0 słów", "1 znak, 1 słowo", "2 znaki, 2 słowa",
                "5 znaków, 1 słowo", "12 znaków, 22 słowa", "22 znaki, 12 słów",
            ]
        default: []
        }
        #expect(expected.count == pairs.count)
        for (index, pair) in pairs.enumerated() {
            #expect(EditorStatusBarView.documentCountText(
                characterCount: pair.0, wordCount: pair.1,
                bundle: resources, locale: Locale(identifier: language)
            ) == expected[index])
        }
    }

    @Test(arguments: ["en", "fr", "ja", "pl"])
    func compiledSelectedCountsUseLocaleForms(_ language: String) throws {
        let url = try #require(Bundle.main.url(forResource: language, withExtension: "lproj"))
        let resources = try #require(Bundle(url: url))
        let counts = [0, 1, 2, 5, 12, 22]
        let expected: [String] = switch language {
        case "en": ["0 selected", "1 selected", "2 selected", "5 selected", "12 selected", "22 selected"]
        case "fr": [
                "0 caractère sélectionné", "1 caractère sélectionné", "2 caractères sélectionnés",
                "5 caractères sélectionnés", "12 caractères sélectionnés", "22 caractères sélectionnés",
            ]
        case "ja": ["0文字選択中", "1文字選択中", "2文字選択中", "5文字選択中", "12文字選択中", "22文字選択中"]
        case "pl": [
                "0 znaków zaznaczonych", "1 znak zaznaczony", "2 znaki zaznaczone",
                "5 znaków zaznaczonych", "12 znaków zaznaczonych", "22 znaki zaznaczone",
            ]
        default: []
        }
        #expect(expected.count == counts.count)
        for (index, count) in counts.enumerated() {
            #expect(EditorStatusBarView.selectedCountText(
                count, bundle: resources, locale: Locale(identifier: language)
            ) == expected[index])
        }
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
