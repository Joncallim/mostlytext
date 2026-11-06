import Contributions
import Foundation
import MarkdownEngine
import Testing

struct TOCLinkedContributionTests {
    @Test func theRealProducerUsesTheSuppliedIndexAndTheDestinationsPlacementToken() async throws {
        let source = "[TOC]\n\n# A\n\n# A\n\n# A-1\n\n## Café\n"
        let document = try await ParseEngine().parse(source, revision: 3)
        let index = try HeadingAnchorIndex(
            document: document, sourceText: source, documentID: "own", recoveryEpoch: UUID(),
            sourceGeneration: 7, reservedIDs: []
        )
        let results = try await TOCContribution(headingIndex: index).run(
            document: document, sourceText: source, sourceGeneration: 99
        )
        try #require(results.count == 1)
        #expect(results[0].sourceGeneration == 99 && results[0].diagnostics.isEmpty)
        guard case let .markdown(list)? = results[0].content?.representation else {
            Issue.record("The production TOC producer must emit linked Markdown")
            return
        }
        #expect(list == "- [A](#a)\n- [A](#a-1)\n- [A\\-1](#a-1-1)\n  - [Café](#caf%C3%A9)")
    }

    @Test func aDifferentSameLengthSourceCannotBorrowAnOtherwiseMatchingIndex() async throws {
        let parser = ParseEngine()
        let original = "[TOC]\n\n# A\n", changed = "[TOC]\n\n# B\n"
        let document = try await parser.parse(original, revision: 3)
        let replacement = try await parser.parse(changed, revision: 3)
        let index = try HeadingAnchorIndex(
            document: document, sourceText: original, documentID: "own", recoveryEpoch: UUID(),
            sourceGeneration: 7, reservedIDs: []
        )
        let results = try await TOCContribution(headingIndex: index).run(
            document: replacement, sourceText: changed, sourceGeneration: 99
        )
        try #require(results.count == 1)
        #expect(results[0].content == nil && results[0].diagnostics.count == 1)
        #expect(results[0].diagnostics.first?.severity == .error)
        #expect(results[0].diagnostics.first?.preventsPublication == true)
        #expect(changed == "[TOC]\n\n# B\n")
    }
}
