import Foundation
import MarkdownEngine
@testable import Preview
import Testing

@Suite("Original source authority on Preview blocks")
struct PreviewBlockSourceAnchorTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func realSourceSlicesCarryTheirOwnExactOriginalRanges(_ ending: String) async throws {
        let source = "---\ntitle: Doc\n---\n\n# 漢😀\n\n\u{600}$x$\u{301} after\n".replacingOccurrences(
            of: "\n",
            with: ending
        )
        let document = try await ParseEngine().parse(source, revision: 1)
        let blocks = PreviewBlock.blocks(from: document, text: source)
        try #require(blocks.count == 2)
        for block in blocks {
            let anchor = try #require(block.sourceAnchor)
            #expect(anchor.sourceSHA256 == document.sourceSHA256)
            #expect(anchor.range.count == block.source.utf16.count)
            let actual = (source as NSString).substring(with: .init(
                location: anchor.range.lowerBound,
                length: anchor.range.count
            ))
            #expect(actual.utf8.elementsEqual(block.source.utf8))
        }
        #expect(PreviewBlock.blocks(from: document, text: source).map(\.id) == blocks.map(\.id))
    }

    @Test func canonicalEquivalentAndLengthMismatchedSourcesNeverAcquireAnOrigin() async throws {
        let source = "# é\n\n$x$"
        let document = try await ParseEngine().parse(source, revision: 1)
        for other in ["# e\u{301}\n\n$x$", "short", "# ë\n\n$x$"] {
            let blocks = PreviewBlock.blocks(from: document, text: other)
            #expect(!blocks.isEmpty)
            #expect(blocks.allSatisfy { $0.sourceAnchor == nil })
        }
    }

    @Test func onlyContainedAuthoredSlicesCanRetainAnOrigin() async throws {
        let source = "before\n\n$x$ after"
        let document = try await ParseEngine().parse(source, revision: 1)
        let original = try #require(PreviewBlock.blocks(from: document, text: source).last)
        let anchor = try #require(original.sourceAnchor)
        let range = (anchor.range.lowerBound + 4) ..< anchor.range.upperBound
        let slice = try #require(anchor.slice(range))
        #expect(slice.sourceSHA256 == anchor.sourceSHA256 && slice.range == range)
        #expect(anchor.slice(0 ..< anchor.range.upperBound) == nil)
        #expect(anchor.slice(anchor.range.lowerBound ..< (anchor.range.upperBound + 1)) == nil)
        #expect(anchor.slice(anchor.range.lowerBound ..< anchor.range.lowerBound) == nil)
        let generated = PreviewBlock(kind: original.kind, source: original.source, lineRange: original.lineRange)
        #expect(generated.sourceAnchor == nil)
        let wrongLength = PreviewBlock(
            kind: original.kind,
            source: "x",
            lineRange: original.lineRange,
            sourceAnchor: anchor
        )
        #expect(wrongLength.sourceAnchor == nil)
    }
}
