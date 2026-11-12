@testable import EditorCore
import Foundation
import Testing

@Suite("Markdown list-contained fence safety")
struct ListFenceSafetyTests {
    private let markdownProfile = LanguageEditingProfileRegistry.profile(for: "markdown")

    @Test("direct list fence suppresses Markdown assist and resumes after its closer")
    func directListFenceGatesActualAssist() {
        for ending in ["\n", "\r\n", "\r"] {
            let inside = ["- ```swift", "  code "].joined(separator: ending) as NSString
            #expect(FencedRegionClassifier.classify(text: inside, atUTF16Offset: inside.length)
                == .fencedCode(languageID: "swift"))
            #expect(markdownAsteriskOutcome(in: inside) == .passthrough)

            let after = ["- ```swift", "  code", "  ```", "Outside prose "]
                .joined(separator: ending) as NSString
            #expect(FencedRegionClassifier.classify(text: after, atUTF16Offset: after.length) == .prose)
            guard case .edit = markdownAsteriskOutcome(in: after) else {
                Issue.record("Markdown delimiter assist did not resume after the list fence")
                continue
            }
        }
    }

    @Test("nested and ordered list markers carry fence content indentation")
    func nestedAndOrderedListFences() {
        for source in [
            "- item\n  - ~~~swift\n    code ",
            "12. ```python\n    code ",
            "> - ```swift\n>   code ",
        ] {
            let text = source as NSString
            guard case .fencedCode = FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length)
            else {
                Issue.record("A list-contained fence was classified as prose: \(source)")
                continue
            }
            #expect(markdownAsteriskOutcome(in: text) == .passthrough)
        }
    }

    @Test("leaving an unclosed list fence resumes prose at the next sibling item")
    func siblingItemEndsUnclosedFence() {
        let text = "- ```swift\n  code\n- next item " as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length) == .prose)
        guard case .edit = markdownAsteriskOutcome(in: text) else {
            Issue.record("Markdown delimiter assist did not resume at sibling list item")
            return
        }
    }

    @Test("an indented fence after a list paragraph stays inside its item")
    func listParagraphThenFence() {
        let text = "- item\n  ```swift\n  code " as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length)
            == .fencedCode(languageID: "swift"))
        #expect(markdownAsteriskOutcome(in: text) == .passthrough)
    }

    @Test("same-line nested list markers retain their content floor")
    func sameLineNestedListMarkers() {
        let text = "- - ```swift\n    code " as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length)
            == .fencedCode(languageID: "swift"))
        #expect(markdownAsteriskOutcome(in: text) == .passthrough)
    }

    @Test("a marker-only item carries its content floor without consuming the next line")
    func markerOnlyListItem() {
        let inside = "-\n  ```swift\n  code " as NSString
        #expect(FencedRegionClassifier.classify(text: inside, atUTF16Offset: inside.length)
            == .fencedCode(languageID: "swift"))
        #expect(markdownAsteriskOutcome(in: inside) == .passthrough)

        let sibling = "-\n- next " as NSString
        #expect(FencedRegionClassifier.classify(text: sibling, atUTF16Offset: sibling.length) == .prose)
    }

    @Test("mixed list and quote prefix is withheld until its container can be classified")
    func mixedListQuotePrefixFailsClosed() {
        let opener = "- > ```swift" as NSString
        #expect(FencedRegionClassifier.classify(text: opener, atUTF16Offset: opener.length) == .unresolved)
        #expect(markdownAsteriskOutcome(in: opener) == .passthrough)

        let text = "- > ```swift\n  > code " as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length) == .unresolved)
        #expect(markdownAsteriskOutcome(in: text) == .passthrough)
    }

    @Test("a top-level quote after a list ends the list; a quote indented inside it remains ambiguous")
    func quoteAfterListDistinguishesContainer() {
        let topLevel = "- item\n> ordinary quote " as NSString
        #expect(FencedRegionClassifier.classify(text: topLevel, atUTF16Offset: topLevel.length) == .prose)

        let nested = "- item\n  > ```swift\n  > code " as NSString
        #expect(FencedRegionClassifier.classify(text: nested, atUTF16Offset: nested.length) == .unresolved)
        #expect(markdownAsteriskOutcome(in: nested) == .passthrough)
    }

    @Test("a blank line does not end an open list-contained fence")
    func blankLineInListFence() {
        let text = "- ```swift\n\n  code " as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length)
            == .fencedCode(languageID: "swift"))
        #expect(markdownAsteriskOutcome(in: text) == .passthrough)
    }

    @Test("list-looking source inside a top-level fence stays literal")
    func listMarkerInsideTopLevelFence() {
        let text = "```swift\n- ```\ncode " as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length)
            == .fencedCode(languageID: "swift"))
        #expect(markdownAsteriskOutcome(in: text) == .passthrough)
    }

    @Test("ambiguous tab indentation inside a list fence fails closed")
    func tabIndentedListContentIsUnresolved() {
        let text = "- ```swift\n\tcode " as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length) == .unresolved)
        #expect(markdownAsteriskOutcome(in: text) == .passthrough)

        let markerTab = "-\t```swift\n  code " as NSString
        #expect(FencedRegionClassifier.classify(text: markerTab, atUTF16Offset: markerTab.length) == .unresolved)
        #expect(markdownAsteriskOutcome(in: markerTab) == .passthrough)
    }

    @Test("excessive nested list prefixes fail closed")
    func excessiveListDepthIsUnresolved() {
        let text = (String(repeating: "- ", count: 33) + "```swift\n" +
            String(repeating: " ", count: 66) + "code ") as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length) == .unresolved)
        #expect(markdownAsteriskOutcome(in: text) == .passthrough)
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
