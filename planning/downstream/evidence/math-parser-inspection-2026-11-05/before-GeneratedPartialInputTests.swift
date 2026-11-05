import Testing
import Foundation
@testable import SwiftUIMath

struct GeneratedPartialInputTests {
    @Test func deterministicPartialEquationCorpus() throws {
        let fragments = ["{", "}", "[", "]", "(", ")", "&", "^", "_", "\\", "$", "%", "\n", "\r\n", "\r",
            "x", "a", "1", " ", "🙂", "\u{301}", "\u{0600}", "\\frac", "\\cfrac", "\\sqrt", "\\text",
            "\\left", "\\right", "\\begin", "\\end", "\\color", "\\colorbox", "\\textcolor", "\\not",
            "\\substack", "\\pmod", "\\limits", "\\matrix", "\\unknown", "matrix", "cases", "#ffffff"]
        var state: UInt64 = 0x4D_54_45_51
        func random(_ upper: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return Int((state >> 32) % UInt64(upper))
        }
        for caseIndex in 0..<50_000 {
            var source = ""
            for _ in 0..<random(24) { source += fragments[random(fragments.count)] }
            let limits = Math.BodyLimits(maximumUTF16Length: 1_024, maximumDepth: 8,
                maximumParserSteps: [1, 2, 3, 8, 32, 256, 4_096][caseIndex % 7])
            let record = try JSONSerialization.data(withJSONObject: ["index": caseIndex, "body": source, "steps": limits.maximumParserSteps], options: [.sortedKeys])
            FileHandle.standardError.write(record + Data([10]))
            _ = try Math.inspectBody(source, limits: limits)
        }
    }
}
