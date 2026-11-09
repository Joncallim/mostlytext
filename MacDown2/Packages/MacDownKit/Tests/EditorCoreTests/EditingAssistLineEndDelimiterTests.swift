@testable import EditorCore
import Foundation
import Testing

@Suite("Editing assists — Markdown line-end delimiters")
struct EditingAssistLineEndDelimiterTests {
    @Test("closing emphasis after a word at line end does not insert an extra delimiter")
    func closingDelimiterAtLineEnd() {
        for delimiter in ["*", "_"] as [Character] {
            for text in ["word", "word\nnext", "word\rnext", "word\r\nnext"] {
                #expect(EditingAssistTestSupport.type(delimiter, in: text, at: 4) == .passthrough,
                        "delimiter \(delimiter) before line ending in \(text.debugDescription)")
            }
        }
    }
}
