import Foundation
@testable import MacDown2
import MarkdownEngine
import Preview
import Testing

@MainActor
@Suite("Preview resource composition ownership")
struct PreviewResourceCompositionOwnershipTests {
    @Test func equalRevisionsFromAnotherParserCannotReusePublishedContributions() async throws {
        let firstText = "![first](first.png)\n"
        let secondText = "![second](second.png)\n"
        let engine = ParseEngine()
        let first = try await engine.parse(firstText, revision: 1)
        let second = try await engine.parse(secondText, revision: 1)
        let firstBlocks = PreviewBlock.blocks(from: first, text: firstText)
        let secondBlocks = PreviewBlock.blocks(from: second, text: secondText)
        let firstID = UUID()
        let secondID = UUID()
        let session = PreviewContributionSession()
        await session.refresh(taskID: .init(documentIdentity: firstID, parsedRevision: 1),
                              document: first, text: firstText, baseBlocks: firstBlocks)
        #expect(session.composition.sourceGeneration == 1)
        #expect(session.composition.blocks?.contains { $0.source.contains("first.png") } == true)
        let pendingSecond = session.displayedBlocks(baseBlocks: secondBlocks, currentRevision: 1,
                                                    documentIdentity: secondID)
        #expect(pendingSecond == secondBlocks,
                "A completed earlier composition cannot borrow a different parser's equal revision")
        await session.refresh(taskID: .init(documentIdentity: secondID, parsedRevision: 1),
                              document: second, text: secondText, baseBlocks: secondBlocks)
        let current = session.displayedBlocks(baseBlocks: secondBlocks, currentRevision: 1,
                                              documentIdentity: secondID)
        #expect(current?.contains { $0.source.contains("second.png") } == true)
        #expect(current?.contains { $0.source.contains("first.png") } == false)
        #expect(session.displayedBlocks(baseBlocks: firstBlocks, currentRevision: 1,
                                        documentIdentity: firstID) == firstBlocks)
    }

    @Test func selectedLanguageChangeHidesOldContributionUntilRecomposed() async throws {
        let text = "[TOC]\n"
        let document = try await ParseEngine().parse(text, revision: 1)
        let base = PreviewBlock.blocks(from: document, text: text)
        let identity = UUID()
        let session = PreviewContributionSession()
        await session.refresh(taskID: .init(documentIdentity: identity, parsedRevision: 1,
                                            localeIdentifier: "en"),
                              document: document, text: text, baseBlocks: base,
                              locale: Locale(identifier: "en"))
        #expect(session.displayedBlocks(baseBlocks: base, currentRevision: 1,
                                        documentIdentity: identity, localeIdentifier: "en") != base)
        #expect(session.displayedBlocks(baseBlocks: base, currentRevision: 1,
                                        documentIdentity: identity, localeIdentifier: "fr") == base)
        #expect(session.displayedDiagnostics(currentRevision: 1,
                                             documentIdentity: identity, localeIdentifier: "fr").isEmpty)
    }
}
