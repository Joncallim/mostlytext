import Foundation
@testable import MarkdownEngine
import Testing

struct HeadingAnchorIndexTests {
    @Test func repeatedHeadingsCarrySourceLocationsAndReserveAuthoredIDs() async throws {
        let source = "---\ntitle: Sample\n---\n# A\n# A\n# A-1\n"
        let parsed = try await ParseEngine().parse(source, revision: 7)
        let epoch = UUID()
        let index = try HeadingAnchorIndex(
            document: parsed, sourceText: source, documentID: "doc-1",
            recoveryEpoch: epoch, sourceGeneration: 9, reservedIDs: ["a", "a-1"]
        )

        #expect(index.headings.map(\.fragment) == ["a-2", "a-3", "a-1-1"])
        #expect(index.headings.map(\.sourceLineRange) == [4 ... 4, 5 ... 5, 6 ... 6])
        #expect(index.headings.map(\.ordinal) == [0, 1, 2])
        #expect(index.headings[0].sourceUTF16Range.lowerBound == (source as NSString).range(of: "# A").location)
        #expect(index.identity.documentID == "doc-1")
        #expect(index.identity.recoveryEpoch == epoch)
        #expect(index.identity.sourceGeneration == 9)
        #expect(index.identity.parseRevision == 7)
        #expect(index.identity.allocatorPolicyVersion == HeadingAnchorAllocator.policyVersion)
    }

    @Test func exactSourceAndLifetimeDefineIndexIdentity() async throws {
        let source = "# Café 東京\n"
        let parsed = try await ParseEngine().parse(source, revision: 3)
        let epoch = UUID()
        let first = try HeadingAnchorIndex(
            document: parsed, sourceText: source, documentID: "doc-1",
            recoveryEpoch: epoch, sourceGeneration: 1, reservedIDs: []
        )
        let same = try HeadingAnchorIndex(
            document: parsed, sourceText: source, documentID: "doc-1",
            recoveryEpoch: epoch, sourceGeneration: 1, reservedIDs: []
        )
        let newLifetime = try HeadingAnchorIndex(
            document: parsed, sourceText: source, documentID: "doc-1",
            recoveryEpoch: UUID(), sourceGeneration: 1, reservedIDs: []
        )
        let changedSource = source + "more"
        let reparsed = try await ParseEngine().parse(changedSource, revision: 4)
        let newSource = try HeadingAnchorIndex(
            document: reparsed, sourceText: changedSource, documentID: "doc-1",
            recoveryEpoch: epoch, sourceGeneration: 2, reservedIDs: []
        )

        #expect(first == same)
        #expect(first.identity != newLifetime.identity)
        #expect(first.identity.sourceSHA256 != newSource.identity.sourceSHA256)
        #expect(first.headings.map(\.fragment) == ["café-東京"])
    }

    @Test func staleParseCannotBeAssignedANewerSourceIdentity() async throws {
        let source = "# Original\n"
        let parsed = try await ParseEngine().parse(source, revision: 1)
        do {
            _ = try HeadingAnchorIndex(
                document: parsed, sourceText: "# Replaced\n", documentID: "doc-1",
                recoveryEpoch: UUID(), sourceGeneration: 2, reservedIDs: []
            )
            Issue.record("A stale parse must not acquire a newer source identity")
        } catch {
            #expect(error as? HeadingAnchorIndex.Error == .sourceDoesNotMatchParse)
        }
    }

    @Test(arguments: [false, true])
    func canonicallyEquivalentDifferentBytesCannotBorrowAParse(frontMatter: Bool) async throws {
        let original = frontMatter ? "---\ntitle: \u{212B}\n---\n# Same\n" : "# \u{212B}\n"
        let other = frontMatter ? "---\ntitle: \u{00C5}\n---\n# Same\n" : "# \u{00C5}\n"
        #expect(original == other)
        #expect(!original.utf8.elementsEqual(other.utf8))
        #expect(SourceMap(text: original) == SourceMap(text: other))
        let parsed = try await ParseEngine().parse(original, revision: 1)
        #expect(throws: HeadingAnchorIndex.Error.sourceDoesNotMatchParse) {
            try HeadingAnchorIndex(
                document: parsed, sourceText: other, documentID: "doc-1",
                recoveryEpoch: UUID(), sourceGeneration: 2, reservedIDs: []
            )
        }
    }

    @Test(arguments: [false, true])
    func independentlyParsedCanonicalSpellingsKeepTheirOwnSourceIdentity(frontMatter: Bool) async throws {
        let first = frontMatter ? "---\ntitle: \u{212B}\n---\n# Same\n" : "# \u{212B}\n"
        let second = frontMatter ? "---\ntitle: \u{00C5}\n---\n# Same\n" : "# \u{00C5}\n"
        let epoch = UUID()
        let parser = ParseEngine()
        let parsedFirst = try await parser.parse(first, revision: 1)
        let parsedSecond = try await parser.parse(second, revision: 1)
        let firstIndex = try HeadingAnchorIndex(
            document: parsedFirst, sourceText: first, documentID: "doc-1",
            recoveryEpoch: epoch, sourceGeneration: 1, reservedIDs: []
        )
        let secondIndex = try HeadingAnchorIndex(
            document: parsedSecond, sourceText: second, documentID: "doc-1",
            recoveryEpoch: epoch, sourceGeneration: 1, reservedIDs: []
        )
        #expect(firstIndex.identity.sourceSHA256 != secondIndex.identity.sourceSHA256)
        #expect(parsedFirst.body.utf8.elementsEqual((frontMatter ? "# Same\n" : first).utf8))
        #expect(parsedSecond.body.utf8.elementsEqual((frontMatter ? "# Same\n" : second).utf8))
        #expect(firstIndex.headings.map(\.fragment) == secondIndex.headings.map(\.fragment))
    }

    @Test(arguments: [false, true])
    func changedFrontMatterDelimitersCannotBorrowTheSameExtractedFields(trailingWhitespace: Bool) async throws {
        let original = "---\ntitle: Same\n--- \n# Same\n"
        let other = trailingWhitespace
            ? "---\ntitle: Same\n---\t\n# Same\n"
            : "---\ntitle: Same\n... \n# Same\n"
        let parsed = try await ParseEngine().parse(original, revision: 1)
        let otherParsed = try await ParseEngine().parse(other, revision: 1)
        #expect(SourceMap(text: original) == SourceMap(text: other))
        #expect(parsed.body.utf8.elementsEqual(otherParsed.body.utf8))
        #expect(parsed.frontMatter?.raw == otherParsed.frontMatter?.raw)
        #expect(parsed.bodyLineOffset == otherParsed.bodyLineOffset)
        #expect(throws: HeadingAnchorIndex.Error.sourceDoesNotMatchParse) {
            try HeadingAnchorIndex(
                document: parsed, sourceText: other, documentID: "doc-1",
                recoveryEpoch: UUID(), sourceGeneration: 2, reservedIDs: []
            )
        }
    }

    @Test func anUnboundManualModelCannotMintASourceIdentity() async throws {
        let source = "# Same\n"
        let parsed = try await ParseEngine().parse(source, revision: 1)
        let unbound = MarkdownDocument(
            body: parsed.body, bodyLineOffset: parsed.bodyLineOffset,
            blocks: parsed.blocks, headings: parsed.headings, frontMatter: parsed.frontMatter,
            sourceMap: parsed.sourceMap, revision: parsed.revision, options: parsed.options
        )
        #expect(unbound.sourceSHA256 == nil)
        #expect(throws: HeadingAnchorIndex.Error.sourceDoesNotMatchParse) {
            try HeadingAnchorIndex(
                document: unbound, sourceText: source, documentID: "doc-1",
                recoveryEpoch: UUID(), sourceGeneration: 1, reservedIDs: []
            )
        }
    }
}
