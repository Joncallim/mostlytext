import Foundation
@testable import MarkdownEngine
import Testing

struct DirectiveSourcePreservationTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func unfinishedDirectivesPreserveOrdinaryBlocksAndSnapshot(eol: String) async throws {
        for prefix in ["", "---\ntitle: Example\n---\n"] {
            for body in [
                "@Note {\nbody café 👩🏽‍💻\n\n# After\n",
                "Intro\n\n@Outer {\n@Inner {\nbody\n}\n\n# After\n",
                "@Note {\n[ref]: https://example.com\n\n# After\n",
            ] {
                let text = (prefix + body).replacingOccurrences(of: "\n", with: eol)
                let engine = ParseEngine()
                let ordinary = try await engine.parse(text, revision: 7)
                let options = MarkdownParseOptions(blockDirectives: true)
                let optedIn = try await engine.parse(text, options: options, revision: 7)
                #expect(optedIn.blocks == ordinary.blocks)
                #expect(optedIn.headings == ordinary.headings)
                #expect(optedIn.body == ordinary.body)
                #expect(optedIn.bodyLineOffset == ordinary.bodyLineOffset)
                #expect(optedIn.frontMatter == ordinary.frontMatter)
                #expect(optedIn.sourceMap == ordinary.sourceMap)
                #expect(optedIn.sourceSHA256 == ordinary.sourceSHA256)
                #expect(optedIn.revision == 7)
                #expect(optedIn.options == options)
                #expect(optedIn.headings.last?.title == "After")
            }
        }
    }

    @Test func referenceDefinitionsDoNotDisableBalancedDirectives() async throws {
        let source = "[ref]: https://example.com\n\n@Note {\nbody\n}\n\n# After\n"
        let document = try await ParseEngine().parse(source, options: .init(blockDirectives: true), revision: 1)
        #expect(document.blocks.contains { $0.kind == .custom("BlockDirective") })
        #expect(document.headings.last?.title == "After")
    }

    @Test func balancedNestedDirectivesRemainEnabled() async throws {
        let source = "@Outer {\n@Inner {\nbody\n}\n}\n\n# After\n"
        let document = try await ParseEngine().parse(source, options: .init(blockDirectives: true), revision: 1)
        #expect(document.blocks.first?.kind == .custom("BlockDirective"))
        #expect(document.blocks.first?.lineRange == 1 ... 5)
        #expect(document.headings.last?.title == "After")
    }

    @Test func manyBlocksKeepTheOptedInCoverageCheckBounded() async throws {
        let source = (0 ..< 3000).map { "Paragraph \($0)\n\n" }.joined() + "@Note {\n\n# After\n"
        let start = ContinuousClock.now
        let document = try await ParseEngine().parse(source, options: .init(blockDirectives: true), revision: 1)
        #expect(document.headings.last?.title == "After")
        #expect(document.blocks.count == 3002)
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
