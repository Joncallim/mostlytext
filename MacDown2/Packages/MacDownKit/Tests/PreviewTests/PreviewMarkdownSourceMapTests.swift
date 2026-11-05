import Foundation
@testable import Preview
import Testing

@Suite("Bounded numeric native Markdown source positions")
struct PreviewMarkdownSourceMapTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func UTF8ColumnsAndInclusiveScalarEndsResolveOnEveryLineEnding(_ ending: String) {
        let source = "漢😀e\u{301}" + ending + "\u{600}MTEQ\u{200C}" + ending
        let map = PreviewMarkdownSourceMap(source)
        #expect(map.range(for: .init(startLine: 1, startColumn: 1, endLine: 1, endColumn: 1)) == NSRange(
            location: 0,
            length: 1
        ))
        #expect(map.range(for: .init(startLine: 1, startColumn: 4, endLine: 1, endColumn: 4)) == NSRange(
            location: 1,
            length: 2
        ))
        #expect(map.range(for: .init(startLine: 1, startColumn: 8, endLine: 1, endColumn: 9)) == NSRange(
            location: 3,
            length: 2
        ))
        #expect(map.range(for: .init(startLine: 2, startColumn: 3, endLine: 2, endColumn: 6)) ==
            NSRange(location: 6 + ending.utf16.count, length: 4))
    }

    @Test func invalidNumericAndInteriorBytePositionsFailWithoutStringIndexConversion() {
        let map = PreviewMarkdownSourceMap("漢😀\ntext\n")
        for position in [
            AttributedString.MarkdownSourcePosition(startLine: 0, startColumn: 1, endLine: 1, endColumn: 1),
            .init(startLine: 1, startColumn: 0, endLine: 1, endColumn: 1),
            .init(startLine: -1, startColumn: 1, endLine: 1, endColumn: 1),
            .init(startLine: 1, startColumn: 2, endLine: 1, endColumn: 4),
            .init(startLine: 1, startColumn: 1, endLine: 1, endColumn: 5),
            .init(startLine: 1, startColumn: 4, endLine: 1, endColumn: 1),
            .init(startLine: 2, startColumn: 1, endLine: 1, endColumn: 1),
            .init(startLine: 3, startColumn: 1, endLine: 3, endColumn: 1),
            .init(startLine: 1, startColumn: 1, endLine: 99, endColumn: 1),
            .init(startLine: 1, startColumn: 1, endLine: 1, endColumn: Int.max),
            .init(startLine: Int.max, startColumn: Int.max, endLine: Int.max, endColumn: Int.max),
        ] {
            #expect(map.range(for: position) == nil)
        }
    }

    @Test func multibyteEndpointIncludesTheWholeLastScalarAndEmptyInputHasNoPosition() {
        let map = PreviewMarkdownSourceMap("x\r\n😀")
        #expect(map.range(for: .init(startLine: 1, startColumn: 1, endLine: 2, endColumn: 1)) == NSRange(
            location: 0,
            length: 5
        ))
        #expect(PreviewMarkdownSourceMap("")
            .range(for: .init(startLine: 1, startColumn: 1, endLine: 1, endColumn: 1)) == nil)
    }
}
