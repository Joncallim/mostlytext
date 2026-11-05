import Foundation
@testable import MacDown2
import Testing

@Suite("Exact authored source observation")
struct SourceAnalysisTextTests {
    @Test func canonicalEqualityDoesNotHideAnAuthoredEdit() {
        for (before, after) in [
            ("café", "cafe\u{301}"),
            ("\u{C5}", "\u{212B}"),
            ("x\u{340}", "x\u{300}"),
        ] {
            #expect(before == after) // The original String observation key suppresses this change.
            #expect(Array(before.utf8) != Array(after.utf8))
            #expect(SourceAnalysisText(before) != SourceAnalysisText(after))
        }
    }

    @Test func equalLengthsDoNotSubstituteForExactSourceIdentity() {
        let before = "x\u{340}", after = "x\u{300}"
        #expect(before.utf8.count == after.utf8.count)
        #expect(before.utf16.count == after.utf16.count)
        #expect(SourceAnalysisText(before) != SourceAnalysisText(after))
    }

    @Test func identicalBytesAreStableAndCapturedTextIsImmutable() throws {
        var source = "🙂 $x$\r\n"
        let snapshot = SourceAnalysisText(source)
        let copied = try #require(String(bytes: Array(source.utf8), encoding: .utf8))
        #expect(snapshot == SourceAnalysisText(copied))
        source += "changed"
        #expect(snapshot != SourceAnalysisText(source))
        #expect(Array(snapshot.text.utf8) == Array("🙂 $x$\r\n".utf8))
    }

    @Test func lineEndingsWhitespaceAndNULRemainAuthoredChanges() {
        let values = ["", " ", "\n", "\r", "\r\n", "\u{0}"]
        for (firstIndex, first) in values.enumerated() {
            for (secondIndex, second) in values.enumerated() {
                #expect((SourceAnalysisText(first) == SourceAnalysisText(second)) == (firstIndex == secondIndex))
            }
        }
    }
}
