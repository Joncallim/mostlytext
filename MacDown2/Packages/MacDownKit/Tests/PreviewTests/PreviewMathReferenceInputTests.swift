import Foundation
@testable import Preview
import Testing

@Suite("Bound original URL authority in rewritten Preview input")
struct PreviewMathReferenceInputTests {
    @Test func originalEndpointsFollowMarkerAndSuffixChanges() throws {
        let source = "[$x$][] after"
        let prefix = "[$x$]: /target\n\n"
        let input = try PreviewMathInput(source: source, prefix: prefix, replacements: [
            .init(id: UUID(), range: 1 ..< 4, expectedSource: "$x$"),
        ], sourceEdits: [.init(range: 4 ..< 7, expectedSource: "][]", replacement: "][$x$]")], references: [
            .init(range: 0 ..< 7, destination: "/target", kind: .link),
        ])
        let reference = try #require(input.references.first)
        #expect(reference.range.lowerBound == prefix.utf16.count)
        #expect(reference.range.upperBound == input.rewritten.utf16.count - " after".utf16.count)
        #expect(reference.destination == "/target")
    }

    @Test func ambiguousAndNonscalarReferenceEndpointsAreRejected() {
        for reference in [0 ..< 1, 2 ..< 4, 1 ..< 3, 0 ..< 20] {
            #expect(throws: PreviewMathInput.Failure.self) {
                try PreviewMathInput(source: "😀$x$", replacements: [
                    .init(id: UUID(), range: 2 ..< 5, expectedSource: "$x$"),
                ], references: [.init(range: reference, destination: "/target", kind: .link)])
            }
        }
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: "a\r\nb", replacements: [], references: [
                .init(range: 0 ..< 2, destination: "/target", kind: .link),
            ])
        }
    }

    @Test func referenceCountAndAggregateDestinationBytesAreBounded() throws {
        let cap = PreviewParserBudget.maximumUTF8Bytes
        let reference = PreviewMathInput.Reference(
            range: 0 ..< 1,
            destination: String(repeating: "x", count: cap),
            kind: .link
        )
        #expect(try PreviewMathInput(source: "x", replacements: [], references: [reference]).references.count == 1)
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: "x", replacements: [], references: [reference, reference])
        }
        let small = PreviewMathInput.Reference(range: 0 ..< 1, destination: "/x", kind: .link)
        #expect(throws: PreviewMathInput.Failure.self) {
            try PreviewMathInput(source: "x", replacements: [], references: Array(repeating: small, count: 1025))
        }
    }

    @Test func indexRejectsOverlapsForeignPositionsAndByteDistinctTargets() throws {
        let first = PreviewMathInput.Reference(range: 2 ..< 8, destination: "/caf%C3%A9", kind: .link)
        let second = PreviewMathInput.Reference(range: 7 ..< 10, destination: "/other", kind: .link)
        #expect(!PreviewMathReferenceIndex([first, second], kind: .link).isValid)
        let index = PreviewMathReferenceIndex([first], kind: .link)
        #expect(try !index.authorizes(
            #require(URL(string: "/caf%C3%A9")),
            range: NSRange(location: NSNotFound, length: 1),
            baseURL: nil
        ))
        #expect(try !index.authorizes(
            #require(URL(string: "/caf%C3%A9")),
            range: NSRange(location: 2, length: 0),
            baseURL: nil
        ))
        #expect(try index.authorizes(
            #require(URL(string: "/caf%C3%A9")),
            range: NSRange(location: 2, length: 6),
            baseURL: nil
        ))
        #expect(try !index.authorizes(
            #require(URL(string: "/cafe%CC%81")),
            range: NSRange(location: 2, length: 6),
            baseURL: nil
        ))
        #expect(try !index.authorizes(
            #require(URL(string: "/caf%C3%A9")),
            range: NSRange(location: 1, length: 7),
            baseURL: nil
        ))
        #expect(try !index.authorizes(
            #require(URL(string: "/caf%C3%A9")),
            range: NSRange(location: 2, length: 7),
            baseURL: nil
        ))
    }
}
