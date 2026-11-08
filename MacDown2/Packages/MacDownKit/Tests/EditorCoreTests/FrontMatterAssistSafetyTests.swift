@testable import EditorCore
import Foundation
import Testing

@Suite("Front matter does not leak into Markdown assists")
struct FrontMatterAssistSafetyTests {
    private let markdownProfile = LanguageEditingProfileRegistry.profile(for: "markdown")

    @Test("an unclosed opener cannot enable Markdown assists during editing")
    func unclosedOpenerFailsSafely() {
        let source = "---\ntitle: unfinished" as NSString
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length) == .unresolved)
        #expect(markdownAsteriskOutcome(in: source) == .passthrough)
    }

    @Test("a closing delimiter beyond the front-matter cap stays unresolved")
    func distantCloserFailsSafely() {
        let source = ("---\ntitle: long\n" + String(repeating: "key: value\n", count: 1005)
            + "---\nafter") as NSString
        let inside = source.range(of: "key: value", options: .backwards).location
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: inside) == .unresolved)
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length) == .unresolved)
        #expect(markdownAsteriskOutcome(in: source) == .passthrough)
    }

    @Test("fence-like YAML content cannot poison the prose after a closed front matter block")
    func closedFrontMatterSkipsItsFenceLikeLines() {
        let source = "---\nsummary: |\n  ```swift\n  example\n---\nbody" as NSString
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length) == .prose)
        guard case .edit = markdownAsteriskOutcome(in: source) else {
            Issue.record("Markdown pairing should resume in prose after front matter")
            return
        }
    }

    @Test("a closer at end of file has no later content to classify")
    func finalCloserIsSafeAtEOF() {
        let source = "---\ntitle: complete\n---" as NSString
        #expect(FencedRegionClassifier.classify(text: source, atUTF16Offset: source.length) == .prose)
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
