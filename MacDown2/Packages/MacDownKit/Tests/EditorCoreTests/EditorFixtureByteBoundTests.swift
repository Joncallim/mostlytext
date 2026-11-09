import Foundation
import Testing

struct EditorFixtureByteBoundTests {
    @Test(arguments: [1_000_000, 10_000_000])
    func performanceCorpusReachesItsRequestedUTF8Size(_ requested: Int) {
        let source = Fixtures.markdown(targetByteCount: requested)
        let bytes = source.utf8.count
        #expect(bytes >= requested)
        #expect(bytes < requested + 512, "The last complete Markdown block should bound overshoot")
        #expect(source.hasSuffix("\n\n"))
        for marker in ["# Heading ", "- List item ", "> A blockquote", "```\n", "The quick brown fox"] {
            #expect(source.contains(marker), "Keep the existing mixed Markdown corpus: \(marker)")
        }
    }
}
