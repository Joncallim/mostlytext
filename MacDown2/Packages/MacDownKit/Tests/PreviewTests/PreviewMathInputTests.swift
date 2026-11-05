import Foundation
@testable import Preview
import Testing

@Suite("Exact source admission for native Preview math")
struct PreviewMathInputTests {
    private let namespace = String(repeating: "A", count: 32)

    private func occurrence(_ source: String, id: UUID = UUID(), in text: String) throws -> PreviewMathInput
        .Replacement {
        let range = (text as NSString).range(of: source, options: .literal)
        try #require(range.location != NSNotFound)
        return .init(id: id, range: range.location ..< NSMaxRange(range), expectedSource: source)
    }

    @Test(arguments: ["\u{600}", "\u{301}", "\u{FE0F}", "\u{200C}", "👩🏽‍💻", "漢"])
    func scalarNeighborsSurviveExactRewriting(_ neighbor: String) throws {
        let source = neighbor + "$x$" + neighbor
        let replacement = try occurrence("$x$", in: source)
        let input = try PreviewMathInput(source: source, replacements: [replacement], namespace: namespace)
        let marker = try #require(input.markers.values.first)
        #expect(input.rewritten.utf8.elementsEqual((neighbor + marker.text + neighbor).utf8))
        #expect(marker.generatedRange.location == neighbor.utf16.count)
        #expect(marker.authoredSource.utf8.elementsEqual("$x$".utf8))
        #expect(input.source.utf8.elementsEqual(source.utf8))
    }

    @Test func ordinaryRepairsAndPrefixParticipateInActualGeneratedCoordinates() throws {
        let source = "[$x$][] and $y$"
        let first = try occurrence("$x$", in: source)
        let second = try occurrence("$y$", in: source)
        let prefix = "[$x$]: /target\n\n"
        let input = try PreviewMathInput(source: source, prefix: prefix, replacements: [second, first], sourceEdits: [
            .init(range: 4 ..< 7, expectedSource: "][]", replacement: "][$x$]"),
        ], namespace: namespace)
        let sorted = input.markers.values.sorted { $0.generatedRange.location < $1.generatedRange.location }
        #expect(sorted.map(\.id) == [first.id, second.id])
        for marker in sorted {
            #expect((input.rewritten as NSString).substring(with: marker.generatedRange).utf8
                .elementsEqual(marker.text.utf8))
        }
        #expect(input.rewritten.hasPrefix(prefix + "["))
        #expect(input.rewritten.contains("][$x$] and "))
    }

    @Test func sourceIdentityUsesBytesRatherThanCanonicalEquality() throws {
        let source = "é"
        let alias = "e\u{301}"
        #expect(source == alias)
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(
                source: source,
                replacements: [.init(id: UUID(), range: 0 ..< 1, expectedSource: alias)]
            )
        }
    }

    @Test func invalidScalarCRLFEmptyAndForeignRangesAreRejected() {
        let source = "😀\r\n$x$"
        for range in [0 ..< 1, 1 ..< 2, 2 ..< 3, 3 ..< 4, 0 ..< 0, 0 ..< 99] {
            #expect(throws: PreviewMathInput.Failure.self) {
                try PreviewMathInput(
                    source: source,
                    replacements: [.init(id: UUID(), range: range, expectedSource: "x")]
                )
            }
        }
    }

    @Test func identitiesAndAllEditRangesMustBeDisjoint() throws {
        let source = "$x$ $y$"
        let id = UUID()
        let first = try occurrence("$x$", id: id, in: source)
        let second = try occurrence("$y$", id: id, in: source)
        #expect(throws: PreviewMathInput.Failure.self) { try PreviewMathInput(
            source: source,
            replacements: [first, second]
        ) }
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: source, replacements: [first], sourceEdits: [
                .init(range: 2 ..< 4, expectedSource: "$ ", replacement: "repair"),
            ])
        }
    }

    @Test func collisionChecksAreLiteralEvenBesideGraphemeExtensions() throws {
        let family = "MTEQ" + namespace + "Z"
        for source in ["\u{600}" + family, family + "\u{301}"] {
            #expect(throws: PreviewMathInput.Failure.self) {
                try PreviewMathInput(source: source, replacements: [], namespace: namespace)
            }
        }
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: "x", prefix: family + "\n\n", replacements: [], namespace: namespace)
        }
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: "x", replacements: [], sourceEdits: [
                .init(range: 0 ..< 1, expectedSource: "x", replacement: family),
            ], namespace: namespace)
        }
    }

    @Test func completeExpandedInputAndEditCountsHaveHardBoundaries() throws {
        let cap = PreviewParserBudget.maximumUTF8Bytes
        let exact = try PreviewMathInput(source: String(repeating: "x", count: cap), replacements: [])
        #expect(exact.rewritten.utf8.count == cap)
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: String(repeating: "x", count: cap + 1), replacements: [])
        }
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: String(repeating: "x", count: cap), prefix: "\n\n", replacements: [])
        }
        let expansion = try PreviewMathInput(
            source: "x",
            replacements: [occurrence("x", in: "x")],
            namespace: namespace
        )
        let markerSize = try #require(expansion.markers.values.first?.text.utf8.count)
        let body = String(repeating: "a", count: cap - markerSize) + "x"
        let atCap = try PreviewMathInput(source: body, replacements: [occurrence("x", in: body)], namespace: namespace)
        #expect(atCap.rewritten.utf8.count == cap)
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(
                source: "a" + body,
                replacements: [occurrence("x", in: "a" + body)],
                namespace: namespace
            )
        }
        let item = try occurrence("x", in: "x")
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: "x", replacements: Array(repeating: item, count: 513))
        }
        let edit = PreviewMathInput.SourceEdit(range: 0 ..< 1, expectedSource: "x", replacement: "a")
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: "x", replacements: [], sourceEdits: Array(repeating: edit, count: 1025))
        }
    }

    @Test(arguments: ["\n\n", "\r\n\r\n", "\r\r"])
    func prefixNeedsItsOwnBlankLine(_ ending: String) throws {
        let input = try PreviewMathInput(source: "body", prefix: "[key]: /target" + ending, replacements: [])
        #expect(input.rewritten.hasSuffix("body"))
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: "body", prefix: "[key]: /target\n", replacements: [])
        }
    }

    @Test func invalidNamespaceAndPrecancelledWorkFailBeforePublication() async {
        for value in ["", "abc", String(repeating: "g", count: 32), String(repeating: "A", count: 33)] {
            #expect(throws: PreviewMathInput.Failure.self) {
                try PreviewMathInput(source: "x", replacements: [], namespace: value)
            }
        }
        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            #expect(throws: CancellationError.self) { try PreviewMathInput(source: "x", replacements: []) }
        }
        task.cancel()
        await task.value
    }
}
