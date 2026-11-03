import AppKit
@testable import Highlighting
import SwiftTreeSitter
import Testing
@testable import TreeSitterClient

@MainActor
struct InputEditGeometryTests {
    private struct Example {
        let source: String
        let range: NSRange
        let replacement: String
        let start: Point
        let oldEnd: Point
        let newEnd: Point
    }

    @Test func actualNeonEditUsesBytePointsFromTheCorrectSnapshots() throws {
        let examples: [Example] = [
            .init(source: "abc", range: NSRange(location: 1, length: 1), replacement: "XY",
                  start: Point(row: 0, column: 2), oldEnd: Point(row: 0, column: 4), newEnd: Point(row: 0, column: 6)),
            .init(source: "a\nbc", range: NSRange(location: 0, length: 3), replacement: "ab\n",
                  start: .zero, oldEnd: Point(row: 1, column: 2), newEnd: Point(row: 1, column: 0)),
            .init(source: "é😀x", range: NSRange(location: 1, length: 2), replacement: "漢",
                  start: Point(row: 0, column: 2), oldEnd: Point(row: 0, column: 6), newEnd: Point(row: 0, column: 4)),
            .init(source: "", range: NSRange(location: 0, length: 0), replacement: "😀\n漢",
                  start: .zero, oldEnd: .zero, newEnd: Point(row: 1, column: 2)),
            .init(source: "ab\nc", range: NSRange(location: 0, length: 4), replacement: "漢\n😀",
                  start: .zero, oldEnd: Point(row: 1, column: 2), newEnd: Point(row: 1, column: 4)),
            .init(source: "😀\n漢", range: NSRange(location: 0, length: 4), replacement: "",
                  start: .zero, oldEnd: Point(row: 1, column: 2), newEnd: .zero),
            .init(source: "a\r\nb", range: NSRange(location: 1, length: 2), replacement: "\n",
                  start: Point(row: 0, column: 2), oldEnd: Point(row: 1, column: 0), newEnd: Point(row: 1, column: 0)),
        ]
        for example in examples {
            let view = NSTextView()
            view.string = example.source
            var revision: UInt64 = 0
            let transform = NeonSyntaxHighlighter.locationTransformer(for: view, revision: { revision })
            // Prime the cache and retain the old endpoint before replacing text.
            let oldEnd = try #require(transform(NSMaxRange(example.range)))
            let replacementLength = (example.replacement as NSString).length
            let delta = replacementLength - example.range.length
            view.string = (example.source as NSString).replacingCharacters(in: example.range, with: example.replacement)
            revision += 1
            let edit = InputEdit(range: example.range, delta: delta, oldEndPoint: oldEnd, transformer: transform)

            // Explicit examples lock the byte/Point contract independently of
            // the host transformer's implementation, including surrogate pairs.
            #expect(edit.startByte == UInt32(example.range.location * 2))
            #expect(edit.oldEndByte == UInt32(NSMaxRange(example.range) * 2))
            #expect(edit.newEndByte == UInt32((example.range.location + replacementLength) * 2))
            #expect(edit.startPoint == example.start)
            #expect(edit.oldEndPoint == example.oldEnd)
            #expect(edit.newEndPoint == example.newEnd)
        }
    }
}
