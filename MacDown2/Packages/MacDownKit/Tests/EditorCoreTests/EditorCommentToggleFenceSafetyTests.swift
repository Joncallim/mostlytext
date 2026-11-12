@testable import EditorCore
import Foundation
import Testing

@Suite("Markdown comment toggle fence safety")
struct EditorCommentToggleFenceSafetyTests {
    private let markdownProfile = LanguageEditingProfileRegistry.profile(for: "markdown")

    @Test("a selection crossing a fence boundary declines instead of commenting its delimiter")
    func fenceAwareProfileDeclinesWideSelectionAcrossFenceBoundary() {
        for ending in ["\n", "\r\n", "\r"] {
            let text = ["prose", "```swift", "let x = 1", "```", "more text"]
                .joined(separator: ending) as NSString
            let lineIndex = EditorLineIndex(text: text)
            let start = text.range(of: "let x").location
            let end = text.range(of: "more text").location + "more text".utf16.count
            let selection = EditorSelectionSet(single: NSRange(location: start, length: end - start))

            let transaction = EditorCommentToggle.toggleCommentTransaction(
                text: text,
                lineIndex: lineIndex,
                selection: selection,
                isMarkdownFormat: true,
                profile: markdownProfile
            )
            #expect(transaction == nil)
        }
    }

    @Test("comment toggle declines on a fence delimiter line itself")
    func fenceDelimiterLineDeclines() {
        let text = "```swift\nlet x = 1\n```\nmore text" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "```", options: .backwards).location
        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: EditorSelectionSet(single: NSRange(location: caret, length: 0)),
            isMarkdownFormat: true,
            profile: markdownProfile
        )
        #expect(transaction == nil)
    }

    @Test("one unsafe Markdown selection declines the whole multi-selection comment command")
    func mixedSafeAndFenceBoundarySelectionsDeclineAtomically() {
        let text = "```swift\nlet x = 1\n```\nprose" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let code = text.range(of: "let x").location
        let closer = text.range(of: "```", options: .backwards).location
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: code, length: 0), NSRange(location: closer, length: 0)],
            primaryIndex: 0
        )
        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text, lineIndex: lineIndex, selection: selection,
            isMarkdownFormat: true, profile: markdownProfile
        )
        #expect(transaction == nil)
    }

    @Test("quoted code declines comment toggle until container-aware insertion exists")
    func quotedCodeDeclines() {
        let text = "> ```swift\n> let x = 1\n> ```\nprose" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "let x").location
        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text, lineIndex: lineIndex,
            selection: EditorSelectionSet(single: NSRange(location: caret, length: 0)),
            isMarkdownFormat: true, profile: markdownProfile
        )
        #expect(transaction == nil)
    }

    @Test("a prose selection enclosing a closed fence declines even when both endpoints are prose")
    func proseAroundClosedFenceDeclines() {
        let text = "before\n~~~swift\ncode\n~~~\nafter" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text, lineIndex: lineIndex,
            selection: EditorSelectionSet(single: NSRange(location: 0, length: text.length)),
            isMarkdownFormat: true, profile: markdownProfile
        )
        #expect(transaction == nil)
    }

    @Test("literal triple backticks inside prose do not disable a safe comment")
    func literalMarkerInsideProseStillComments() {
        let text = "before ```inline``` after" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text, lineIndex: lineIndex,
            selection: EditorSelectionSet(single: NSRange(location: 0, length: text.length)),
            isMarkdownFormat: true, profile: markdownProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "<!--before ```inline``` after-->")
    }

    @Test("an excessive number of candidate marker lines fails closed")
    func manyMarkerLinesDeclineBoundedly() {
        let text = String(repeating: "text ```inline```\n", count: 65) as NSString
        let lineIndex = EditorLineIndex(text: text)
        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text, lineIndex: lineIndex,
            selection: EditorSelectionSet(single: NSRange(location: 0, length: text.length)),
            isMarkdownFormat: true, profile: markdownProfile
        )
        #expect(transaction == nil)
    }
}
