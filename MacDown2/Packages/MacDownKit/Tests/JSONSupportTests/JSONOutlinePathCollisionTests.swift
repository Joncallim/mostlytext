import Foundation
import JSONSupport
import Testing

@Suite("JSON outline path collisions")
struct JSONOutlinePathCollisionTests {
    private let source = #"{"a.b":{"x":1},"a":{"b":{"x":2}},"arr":[4],"arr[0]":5,"":6,"\u00E9":7,"e\u0301":8}"#

    @Test func everyNodeHasItsOwnLookupAndCollapseIdentity() throws {
        let roots = try items(source)
        let all = flatten(roots)
        #expect(JSONOutlineBuilder.allIDs(roots).count == all.count)
        for node in all {
            #expect(JSONOutlineBuilder.item(withID: node.id, in: roots)?.sourceRange == node.sourceRange)
            let visible = JSONOutlineBuilder.visibleRows(roots, collapsed: [node.id])
            #expect(visible.count == all.count - flatten(node.children).count)
        }
    }

    @Test func identitiesSurviveFormattingAndObjectReordering() throws {
        let before = try items(source)
        guard case let .formatted(formatted) = JSONFormatter.format(source, options: JSONFormatOptions(sortKeys: true))
        else {
            Issue.record("Expected valid source to format")
            return
        }
        let after = try items(formatted)
        #expect(JSONOutlineBuilder.allIDs(before) == JSONOutlineBuilder.allIDs(after))
        #expect(JSONOutlineBuilder.allIDs(after).count == flatten(after).count)
    }

    @Test func alternateEscapesOfOneDecodedKeyHaveTheSameIdentity() throws {
        let literal = try items(#"{"a.b":1}"#)
        let escaped = try items(#"{"a\u002eb":1}"#)
        #expect(literal.first?.children.first?.id == escaped.first?.children.first?.id)
    }

    private func items(_ text: String) throws -> [ContentOutlineItem] {
        let result = JSONAnalyzer.analyze(text)
        try #require(result.isValid)
        return result.outlineItems
    }

    private func flatten(_ items: [ContentOutlineItem]) -> [ContentOutlineItem] {
        items.flatMap { [$0] + flatten($0.children) }
    }
}
