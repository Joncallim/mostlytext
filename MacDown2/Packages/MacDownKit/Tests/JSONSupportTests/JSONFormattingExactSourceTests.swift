import Foundation
import JSONSupport
import Testing

@Suite("JSON formatting exact source")
struct JSONFormattingExactSourceTests {
    @Test func rejectsCanonicalUnicodeSubstitutionWithUnchangedCounters() {
        let decomposed = "{\"name\":\"e\u{301}\"}"
        let composed = "{\"name\":\"\u{E9}\"}"
        #expect(decomposed == composed)
        #expect(!decomposed.utf8.elementsEqual(composed.utf8))

        for (original, current) in [(decomposed, composed), (composed, decomposed)] {
            let baseline = JSONFormattingBaseline(
                text: original, documentGeneration: 7, editorContentRevision: 42, options: .pretty
            )
            #expect(!baseline.accepts(text: current, documentGeneration: 7, editorContentRevision: 42))
            #expect(baseline.accepts(text: original, documentGeneration: 7, editorContentRevision: 42))
            #expect(!baseline.accepts(text: original, documentGeneration: 8, editorContentRevision: 42))
            #expect(!baseline.accepts(text: original, documentGeneration: 7, editorContentRevision: 43))
        }
    }
}
