import Foundation
import Testing

struct ParserCorpusByteBoundTests {
    @Test(arguments: [1_000_000, 1_048_576, 10_000_000, 10_485_760])
    func performanceCorpusActuallyReachesTheRequestedUTF8ByteBound(_ requested: Int) {
        let source = Fixtures.markdown(targetByteCount: requested)
        #expect(source.utf8.count >= requested)
        #expect(source.hasSuffix("\n\n"), "Keep complete Markdown blocks at the final boundary")
        for marker in [
            "# Heading ",
            "- List item ",
            "> A blockquote",
            "```swift\n",
            "| A | B |",
            "The quick brown fox",
        ] {
            #expect(source.contains(marker), "Preserve the existing mixed Markdown corpus: \(marker)")
        }
    }
}
