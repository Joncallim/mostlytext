import Foundation
@testable import MarkdownEngine
import Testing

struct SourceReferenceSelectionTests {
    private func range(_ text: String, in source: String) throws -> Range<Int> {
        let value = (source as NSString).range(of: text, options: .literal)
        try #require(value.location != NSNotFound)
        return value.location ..< NSMaxRange(value)
    }

    @Test func aBlockReceivesOnlyItsOwnActualDirectAndReferenceTargets() async throws {
        let block = "[direct](/first) [ref][key] ![image](/picture)"
        let source = "[key]: /target\n\n" + block + "\n\n[other](/other) ![unrelated](/else)"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let index = try MarkdownReferenceReplayIndex(facts: facts)
        let selection = try index.references(for: range(block, in: source), sourceSHA256: facts.sourceSHA256)
        #expect(selection.links.map(\.destination) == ["/first", "/target"])
        #expect(selection.images.map(\.source) == ["/picture"])
        #expect(selection.links.allSatisfy { $0.fullRange.lowerBound >= 0 })
        #expect(throws: MarkdownReferenceReplayIndex.Failure.self) {
            try index.references(for: range(block, in: source), sourceSHA256: "foreign")
        }
    }

    @Test func fragmentBoundariesCannotCutDirectLinksOrNestedImageResources() async throws {
        let block = "[![alt](/picture)](/outer)"
        let source = "before\n\n" + block + "\n\nafter"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let index = try MarkdownReferenceReplayIndex(facts: facts)
        let complete = try range(block, in: source)
        let selection = try index.references(for: complete, sourceSHA256: facts.sourceSHA256)
        #expect(selection.links.count == 1 && selection.images.count == 1)
        for partial in [
            (complete.lowerBound + 1) ..< complete.upperBound,
            complete.lowerBound ..< (complete.upperBound - 1),
        ] {
            #expect(throws: MarkdownReferenceReplayIndex.Failure.self) {
                try index.references(for: partial, sourceSHA256: facts.sourceSHA256)
            }
        }
    }

    @Test func unrelatedTextHasNoFabricatedTargetsAndInvalidIntervalsAreRejected() async throws {
        let source = "[link](/target)\n\nplain"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let index = try MarkdownReferenceReplayIndex(facts: facts)
        let plain = try index.references(for: range("plain", in: source), sourceSHA256: facts.sourceSHA256)
        #expect(plain.links.isEmpty && plain.images.isEmpty)
        for invalid in [-1 ..< 0, 0 ..< 0] {
            #expect(throws: MarkdownReferenceReplayIndex.Failure.self) {
                try index.references(for: invalid, sourceSHA256: facts.sourceSHA256)
            }
        }
    }
}
