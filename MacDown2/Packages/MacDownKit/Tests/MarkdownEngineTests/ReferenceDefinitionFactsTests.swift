import Foundation
@testable import MarkdownEngine
import Testing

@Suite("Bound original reference replay authority")
struct ReferenceDefinitionFactsTests {
    private func span(_ text: String, in source: String) throws -> Range<Int> {
        let range = (source as NSString).range(of: text, options: .literal)
        try #require(range.location != NSNotFound)
        return range.location ..< NSMaxRange(range)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func actualUsesIncludeImagesAndOriginalFrontMatterOffsets(_ ending: String) async throws {
        let body = "---\ntitle: Doc\n---\n\n```\n[key]: /wrong\n```\n\n" +
            "> - [key]:\n>     /right\n>     \"title\"\n\n漢😀 [label][key] ![image][key]"
        let source = body.replacingOccurrences(of: "\n", with: ending)
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        #expect(facts.sourceSHA256 == document.sourceSHA256)
        let definitions = facts.referenceDefinitions
        try #require(definitions.count == 1)
        let definition = try #require(definitions.first)
        #expect(!definition.source.contains("/wrong"))
        #expect(definition.source.contains("/right"))
        #expect(try definition.useRanges == [span("[label][key]", in: source), span("![image][key]", in: source)])
        let index = try MarkdownReferenceReplayIndex(facts: facts)
        let block = try span("漢😀 [label][key] ![image][key]", in: source)
        let prefix = try index.prefix(for: block, sourceSHA256: facts.sourceSHA256, maximumUTF8Bytes: 65536)
        let replayed = try await ParseEngine().parse(prefix + "[label][key]", revision: 2)
        #expect(replayed.sourceFacts?.links.map(\.destination) == ["/right"])
        #expect(replayed.sourceFacts?.links.map(\.title) == ["title"])
    }

    @Test func actualFirstWinnerIsSelectedOnceAndUnusedDefinitionsCannotMintAuthority() async throws {
        let source = "[key]: /first\n[key]: /later\n[unused]: /unused\n\n[one][key] [two][key]"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        #expect(facts.referenceDefinitions.map(\.useRanges.count) == [2, 0, 0])
        let index = try MarkdownReferenceReplayIndex(facts: facts)
        let range = try span("[one][key] [two][key]", in: source)
        let prefix = try index.prefix(for: range, sourceSHA256: facts.sourceSHA256, maximumUTF8Bytes: 65536)
        #expect(prefix.contains("/first"))
        #expect(!prefix.contains("/later") && !prefix.contains("/unused"))
        #expect(prefix.utf8.elementsEqual((facts.referenceDefinitions[0].source + "\n\n").utf8))
        let exact = try index.prefix(for: range, sourceSHA256: facts.sourceSHA256, maximumUTF8Bytes: prefix.utf8.count)
        #expect(exact.utf8.elementsEqual(prefix.utf8))
        #expect(throws: MarkdownReferenceReplayIndex.Failure.self) {
            try index.prefix(for: range, sourceSHA256: facts.sourceSHA256, maximumUTF8Bytes: prefix.utf8.count - 1)
        }
        #expect(throws: MarkdownReferenceReplayIndex.Failure.self) {
            try index.prefix(for: range, sourceSHA256: "foreign", maximumUTF8Bytes: 65536)
        }
        #expect(try index.prefix(for: 0 ..< 1, sourceSHA256: facts.sourceSHA256, maximumUTF8Bytes: 0).isEmpty)
    }

    @Test func partialNestedLinkAndImageUsesCannotAuthorizeASplitFragment() async throws {
        let source = "[image]: /image\n[outer]: /outer\n\n[![alt][image]][outer]"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let index = try MarkdownReferenceReplayIndex(facts: facts)
        let range = try span("[![alt][image]][outer]", in: source)
        let complete = try index.prefix(for: range, sourceSHA256: facts.sourceSHA256, maximumUTF8Bytes: 65536)
        #expect(complete.contains("/image") && complete.contains("/outer"))
        for partial in [(range.lowerBound + 1) ..< range.upperBound, range.lowerBound ..< (range.upperBound - 1)] {
            #expect(throws: MarkdownReferenceReplayIndex.Failure.self) {
                try index.prefix(for: partial, sourceSHA256: facts.sourceSHA256, maximumUTF8Bytes: 65536)
            }
        }
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func directiveOptInKeepsOrdinaryWholeBodyReferenceScopeForBothConsumers(_ ending: String) async throws {
        let source = "[key]: /right\n\n@Note {\n  [inside][key]\n}\n\n[outside][key]".replacingOccurrences(
            of: "\n",
            with: ending
        )
        let ordinary = try await ParseEngine().parse(source, revision: 1)
        let structural = try await ParseEngine().parse(source, options: .init(blockDirectives: true), revision: 2)
        #expect(ordinary.blocks != structural.blocks)
        #expect(ordinary.sourceFacts == structural.sourceFacts)
        #expect(structural.sourceFacts?.referenceDefinitions.first?.useRanges.count == 2)
        #expect(structural.options.blockDirectives)
    }

    @Test func invalidProjectedReferenceCoordinatesFailClosed() {
        let source = "漢"
        for use in [
            MarkdownSourcePoint(line: 1, column: 2) ..< MarkdownSourcePoint(line: 1, column: 4),
            MarkdownSourcePoint(line: 1, column: 1) ..< MarkdownSourcePoint(line: 2, column: 1),
            MarkdownSourcePoint(line: 1, column: 1) ..< MarkdownSourcePoint(line: 1, column: 1),
        ] {
            let facts = MarkdownSourceFactProjection.project(
                source: source, sourceSHA256: "fixture", root: 0,
                referenceDefinitions: [.init(source: "[key]: /never", useRanges: [use])],
                children: { _ in [] }, describe: { _ in MarkdownSourceNode(kind: .other, range: nil) }
            )
            #expect(facts == nil)
        }
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func imageTargetsHaveOriginalRangesWhileImageContentsStayLiteral(_ ending: String) async throws {
        let source = "[key]: /original \"image title\"\n\n![label $literal$][key] [linked ![nested](/pic)](/link)"
            .replacingOccurrences(of: "\n", with: ending)
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        #expect(facts.images.map(\.source) == ["/original", "/pic"])
        #expect(facts.images.map(\.title) == ["image title", nil])
        #expect(try facts.images.map(\.fullRange) == [
            span("![label $literal$][key]", in: source), span("![nested](/pic)", in: source),
        ])
        #expect(facts.images.allSatisfy { facts.literalRanges.contains($0.fullRange) })
        #expect(facts.links.map(\.destination) == ["/link"])
    }
}
