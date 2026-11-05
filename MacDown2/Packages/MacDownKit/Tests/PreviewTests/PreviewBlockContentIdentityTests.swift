import Foundation
@testable import Preview
import Testing

struct PreviewBlockContentIdentityTests {
    private func identity(_ input: PreviewMathInput, frame: UUID = UUID(),
                          base: URL? = nil) -> PreviewBlockContentIdentity {
        .init(source: input.source, baseURL: base, input: input, frameID: frame, guarded: true)
    }

    @Test func unrelatedFramesRetainOrdinaryContentAndPendingZeroAuthorityHasTheSameResult() throws {
        let source = "**ordinary**"
        let input = try PreviewMathInput(source: source, replacements: [])
        let ready = identity(input)
        #expect(ready == identity(input))
        let pending = PreviewBlockContentIdentity(source: source, baseURL: nil, input: nil, frameID: nil, guarded: true)
        #expect(pending == ready)
        #expect(Set([pending, ready]).count == 1)
        let legacy = PreviewBlockContentIdentity(source: source, baseURL: nil, input: nil, frameID: nil, guarded: false)
        #expect(legacy != ready)
    }

    @Test func losingAnOriginalTargetInvalidatesIdenticalRewrittenMarkdown() throws {
        let source = "[one][key] and [two][key]"
        let prefix = "[key]: /same\n\n"
        let first = PreviewMathInput.Reference(range: 0 ..< 10, destination: "/same", kind: .link)
        let second = PreviewMathInput.Reference(range: 15 ..< 25, destination: "/same", kind: .link)
        let full = try PreviewMathInput(source: source, prefix: prefix, replacements: [], references: [first, second])
        let reduced = try PreviewMathInput(source: source, prefix: prefix, replacements: [], references: [first])
        #expect(full.rewritten.utf8.elementsEqual(reduced.rewritten.utf8))
        #expect(identity(full) != identity(reduced))
    }

    @Test func exactSourceSpellingAndBaseURLRemainPartOfNativeIdentity() throws {
        let composed = try PreviewMathInput(source: "caf\u{00E9}", replacements: [])
        let decomposed = try PreviewMathInput(source: "cafe\u{0301}", replacements: [])
        #expect(composed.source == decomposed.source)
        #expect(identity(composed) != identity(decomposed))
        let source = try PreviewMathInput(source: "same", replacements: [])
        #expect(identity(source, base: URL(fileURLWithPath: "/one/a.md")) !=
            identity(source, base: URL(fileURLWithPath: "/two/a.md")))
    }

    @Test func ownMathOccurrencesCannotReuseADifferentNativeFrame() throws {
        let input = try PreviewMathInput(source: "$x$", replacements: [
            .init(id: UUID(), range: 0 ..< 3, expectedSource: "$x$"),
        ])
        #expect(identity(input, frame: UUID()) != identity(input, frame: UUID()))
    }
}
