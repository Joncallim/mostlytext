@testable import MacDown2
import Preview
import Testing

@Suite("PreviewDisplayCache")
struct PreviewDisplayCacheTests {
    @Test func sameRevisionAndBlocksReuseTheCachedSnapshot() {
        let block = PreviewBlock(kind: .paragraph, source: "plain", lineRange: 1 ... 1)
        var cache = PreviewDisplayCache()
        var calls = 0
        let preprocess: ([PreviewBlock]?) -> [PreviewBlock]? = { blocks in
            calls += 1
            return blocks
        }

        cache.update(revision: 7, blocks: [block], preprocess: preprocess)
        let firstOutput = cache.output
        cache.update(revision: 7, blocks: [block], preprocess: preprocess)

        #expect(calls == 1)
        #expect(cache.output == firstOutput)
        #expect(cache.revision == 7)
        cache.reset()
        cache.update(revision: 7, blocks: [block], preprocess: preprocess)
        #expect(calls == 2)
    }

    @Test func revisionChangePreservesAuthoredMalformedAndMultilineMath() {
        let first = PreviewBlock(kind: .paragraph, source: "before", lineRange: 1 ... 1)
        let second = PreviewBlock(kind: .paragraph, source: "$\\frac{1}{$\r\n$$\r\nx + y\r\n$$", lineRange: 1 ... 1)
        var cache = PreviewDisplayCache()

        cache.update(revision: 1, blocks: [first])
        cache.update(revision: 2, blocks: [second])

        #expect(cache.revision == 2)
        #expect(cache.input == [second])
        #expect(cache.output?.first?.source.utf8.elementsEqual(second.source.utf8) == true)
        #expect(cache.output?.first?.sourceAnchor == second.sourceAnchor)
    }

    @Test func aNewCompositionAtTheSameRevisionAlsoInvalidates() {
        let first = PreviewBlock(kind: .paragraph, source: "first", lineRange: 1 ... 1)
        let second = PreviewBlock(kind: .paragraph, source: "second", lineRange: 1 ... 1)
        var cache = PreviewDisplayCache()

        cache.update(revision: 3, blocks: [first])
        cache.update(revision: 3, blocks: [second])

        #expect(cache.input == [second])
        #expect(cache.output == [second])
    }

    @Test func nilDisplayInvalidatesTheCache() {
        let block = PreviewBlock(kind: .paragraph, source: "body", lineRange: 1 ... 1)
        var cache = PreviewDisplayCache()
        cache.update(revision: 4, blocks: [block])
        cache.update(revision: 5, blocks: nil)

        #expect(cache.revision == nil)
        #expect(cache.input == nil)
        #expect(cache.output == nil)
    }
}
