import Foundation
import MarkdownEngine
@testable import Preview
import Testing

struct DirectivePreviewSourceTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func unfinishedDirectiveRetainsEveryVisibleBlock(eol: String) async throws {
        let text = ["---", "title: Example", "---", "@Note {", "body café 👩🏽‍💻", "", "# After", ""].joined(separator: eol)
        let engine = ParseEngine()
        let ordinary = try await engine.parse(text, revision: 1)
        let optedIn = try await engine.parse(text, options: .init(blockDirectives: true), revision: 1)
        let expected = PreviewBlock.blocks(from: ordinary, text: text)
        let actual = PreviewBlock.blocks(from: optedIn, text: text)
        #expect(actual == expected)
        #expect(actual.contains { $0.source.contains("body café 👩🏽‍💻") })
        #expect(actual.last?.source == "# After")
    }

    @Test func balancedDirectivePassesItsSourceToPreviewUnchanged() async throws {
        let text = "@Note {\nbody\n}\n"
        let document = try await ParseEngine().parse(text, options: .init(blockDirectives: true), revision: 1)
        let block = try #require(PreviewBlock.blocks(from: document, text: text).first)
        #expect(block.kind == .custom("BlockDirective"))
        #expect(block.source == "@Note {\nbody\n}")
    }
}
