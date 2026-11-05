import Foundation
import JSONSupport
import OutlineUI
import Testing

@MainActor
@Suite("JSON outline exact source")
struct JSONOutlineExactSourceTests {
    @Test func canonicalUnicodeEditRebuildsOriginalSourceRanges() throws {
        let decomposed = "{\"name\":\"e\u{301}\"}"
        let composed = "{\"name\":\"\u{E9}\"}"
        for (before, after) in [(decomposed, composed), (composed, decomposed)] {
            let controller = OutlineController()
            controller.updateJSON(result: JSONAnalyzer.analyze(before), formatID: "json")
            controller.updateJSON(result: JSONAnalyzer.analyze(after), formatID: "json")
            #expect(controller.jsonRebuildCount == 2)
            #expect(controller.jsonItems.first?.sourceRange.upperBound == after.utf16.count)
            let leaf = try #require(controller.jsonItems.first?.children.first)
            controller.activateJSON(leaf.id)
            let range = try #require(controller.pendingJSONJumpSourceRange)
            let expected = try #require(JSONAnalyzer.analyze(after).outlineItems.first?.children.first?.sourceRange)
            #expect(range == expected)

            controller.updateJSON(result: JSONAnalyzer.analyze(after), formatID: "json")
            #expect(controller.jsonRebuildCount == 2)
        }
    }
}
