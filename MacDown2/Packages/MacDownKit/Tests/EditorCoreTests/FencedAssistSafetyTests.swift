@testable import EditorCore
import Foundation
import Testing

@Suite("Fenced Markdown assists fail safely")
struct FencedAssistSafetyTests {
    private let markdownProfile = LanguageEditingProfileRegistry.profile(for: "markdown")

    @Test("a tilde line cannot close a backtick fence")
    func mismatchedMarkerStaysCode() {
        let source = "```swift\ncode\n~~~\nmore code" as NSString
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length)
            == .fencedCode(languageID: "swift"))
        #expect(markdownAsteriskOutcome(in: source) == .passthrough)
    }

    @Test("a shorter marker run cannot close a longer fence")
    func shorterCloserStaysCode() {
        let source = "````swift\ncode\n```\nmore code" as NSString
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length)
            == .fencedCode(languageID: "swift"))
        #expect(markdownAsteriskOutcome(in: source) == .passthrough)
    }

    @Test("a matching marker with trailing text cannot close a fence")
    func trailingTextCannotCloseFence() {
        let source = "```swift\ncode\n```not a closer\nmore code" as NSString
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length)
            == .fencedCode(languageID: "swift"))
        #expect(markdownAsteriskOutcome(in: source) == .passthrough)
    }

    @Test("a valid matching closer resumes Markdown prose")
    func matchingCloserRestoresProse() {
        let source = "````swift\ncode\n`````\nmore prose" as NSString
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length) == .prose)
        guard case .edit = markdownAsteriskOutcome(in: source) else {
            Issue.record("Markdown pairing should resume after a matching closer")
            return
        }
    }

    @Test("invalid closer lines do not prevent a later valid closure")
    func laterMatchingCloserRestoresProse() {
        for sourceText in [
            "```swift\ncode\n~~~\ncode\n```\nmore prose",
            "````swift\ncode\n```\ncode\n````\nmore prose",
        ] {
            let source = sourceText as NSString
            #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length) == .prose)
            guard case .edit = markdownAsteriskOutcome(in: source) else {
                Issue.record("Markdown pairing should resume after the later valid closer")
                continue
            }
        }
    }

    @Test("a fence beyond the bounded scan cannot enable Markdown assists")
    func distantOpenerFailsSafely() {
        let source = ("```swift\n" + String(repeating: "code line\n", count: 5100) + "more code") as NSString
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length) != .prose)
        #expect(markdownAsteriskOutcome(in: source) == .passthrough)
    }

    @Test("comment toggle declines when a distant opener leaves fence state unresolved")
    func unresolvedCommentToggleDeclines() {
        let source = ("```swift\n" + String(repeating: "code line\n", count: 5100) + "more code") as NSString
        let lineIndex = EditorLineIndex(text: source)
        let caret = source.range(of: "more code").location
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: caret) == .unresolved)
        #expect(EditorCommentToggle.toggleCommentTransaction(
            text: source,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: true,
            profile: markdownProfile
        ) == nil)
    }

    private func markdownAsteriskOutcome(in source: NSString) -> EditingAssistOutcome {
        let caret = source.length
        return MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: caret, length: 0), string: "*"),
            text: source,
            selection: NSRange(location: caret, length: 0),
            configuration: .markdownDefault,
            profile: markdownProfile
        )
    }
}
