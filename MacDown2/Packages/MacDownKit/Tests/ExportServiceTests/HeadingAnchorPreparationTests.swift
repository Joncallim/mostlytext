@testable import ExportService
import Foundation
import MarkdownEngine
import Testing

struct HeadingAnchorPreparationTests {
    @Test func ordinaryMarkdownUsesTheSharedAllocatorAndOriginalLifetime() async throws {
        let source = "# A\n\n# A\n\n# A-1\n\n## !!!\n\n# Café 東京\n"
        let document = try await ParseEngine().parse(source, revision: 7)
        let epoch = UUID()
        let result = try await HeadingAnchorPreparation.prepare(
            document: document, sourceText: source, documentID: "own", recoveryEpoch: epoch, sourceGeneration: 9
        )
        #expect(result.index.headings.map(\.fragment) == ["a", "a-1", "a-1-1", "section", "café-東京"])
        #expect(result.index.identity.documentID == "own" && result.index.identity.recoveryEpoch == epoch)
        #expect(result.index.identity.sourceGeneration == 9 && result.index.identity.parseRevision == 7)
        #expect(!result.usedDOMAnalysis && result.authoredIdentifiers.isEmpty)
    }

    @Test func emittedRawIdentifiersReserveExactDecodedValuesIncludingBothUnicodeSpellings() async throws {
        let source = """
        ---
        title: Title
        ---

        <div id='cafe&#x301;'>Decomposed</div>
        <a name='caf&#233;'>Composed</a>

        # Café
        """
        let result = try await prepare(source)
        #expect(result.usedDOMAnalysis)
        #expect(result.authoredIdentifiers.count == 2)
        #expect(Set(result.authoredIdentifiers.map { Data($0.utf8) }).count == 2)
        #expect(result.index.headings.map(\.fragment) == ["café-1"])
        #expect(result.index.headings.first?.sourceLineRange.lowerBound == 8)
    }

    @Test func aDistinctDecomposedIdentifierDoesNotConsumeTheComposedHeading() async throws {
        let result = try await prepare("<div id='cafe&#x301;'>Raw</div>\n\n# Café\n")
        #expect(result.usedDOMAnalysis)
        #expect(result.index.headings.map(\.fragment) == ["café"])
        #expect(result.authoredIdentifiers.first?.utf8.elementsEqual("cafe\u{301}".utf8) == true)
    }

    @Test func codeAndEscapedMarkupDoNotInventAuthoredReservations() async throws {
        let source = "# Target\n\n`<span id=target>`\n\n```html\n<div id=target>\n```\n\n\\<b id=target>\n"
        let result = try await prepare(source)
        #expect(result.index.headings.map(\.fragment) == ["target"])
        #expect(!result.usedDOMAnalysis && result.authoredIdentifiers.isEmpty)
    }

    @Test func anEmptyHeadingInventoryDoesNotAcquireADOMGate() async throws {
        let result = try await prepare("<div title='unterminated>\n")
        #expect(result.index.headings.isEmpty)
        #expect(!result.usedDOMAnalysis)
    }

    @Test func malformedMarkupCannotPublishAnUnverifiableHeadingIndex() async throws {
        await #expect(throws: HeadingAnchorPreparation.Failure.unverifiableMarkup) {
            try await prepare("<div title='unterminated>\n\n# Target\n")
        }
    }

    @Test func aDifferentSourceCannotBorrowThePublishedParse() async throws {
        let document = try await ParseEngine().parse("# A\n", revision: 1)
        await #expect(throws: HeadingAnchorPreparation.Failure.sourceMismatch) {
            try await HeadingAnchorPreparation.prepare(
                document: document, sourceText: "# B\n", documentID: "own", recoveryEpoch: UUID(), sourceGeneration: 1
            )
        }
    }

    @Test func pureMarkdownAboveTheDOMBudgetStillBuildsItsIndex() async throws {
        let source = "# Target\n\n" + String(repeating: "ordinary text ", count: 650_000)
        #expect(source.utf8.count > EmittedHeadingDOM.maximumAnalyzedBytes)
        let result = try await prepare(source)
        #expect(result.index.headings.map(\.fragment) == ["target"])
        #expect(!result.usedDOMAnalysis)
    }

    @Test func actualOversizedAuthoredMarkupRetainsTheExistingDOMAnalysisBudget() async throws {
        let source = "<div id=authored>Raw</div>\n\n# Target\n\n"
            + String(repeating: "ordinary text ", count: 650_000)
        await #expect(throws: HeadingAnchorPreparation.Failure.unverifiableMarkup) {
            try await prepare(source)
        }
    }

    @Test func oversizedSourceIsRejectedBeforeRenderingAnUnrelatedParse() async throws {
        let document = try await ParseEngine().parse("# Target\n", revision: 1)
        let source = String(repeating: "x", count: ExportResourceBudget.standard.maxSourceUTF8Bytes + 1)
        await #expect(throws: HeadingAnchorPreparation.Failure.sourceBudgetExceeded) {
            try await HeadingAnchorPreparation.prepare(
                document: document, sourceText: source, documentID: "own", recoveryEpoch: UUID(), sourceGeneration: 1
            )
        }
    }

    @Test func anOversizedHeadingInventoryIsRejectedBeforeAllocatingNavigationTargets() async throws {
        let source = String(repeating: "# A\n\n", count: HeadingAnchorPreparation.maximumHeadingCount + 1)
        let document = try await ParseEngine().parse(source, revision: 1)
        #expect(document.headings.count == HeadingAnchorPreparation.maximumHeadingCount + 1)
        await #expect(throws: HeadingAnchorPreparation.Failure.headingBudgetExceeded) {
            try await HeadingAnchorPreparation.prepare(
                document: document, sourceText: source, documentID: "own", recoveryEpoch: UUID(), sourceGeneration: 1
            )
        }
        let admitted = try await prepare(String(source.dropLast("# A\n\n".count)))
        #expect(admitted.index.headings.count == HeadingAnchorPreparation.maximumHeadingCount)
        #expect(admitted.index.headings.last?.fragment == "a-16383")
        #expect(!admitted.usedDOMAnalysis)
    }

    @Test func cancellationDoesNotReturnAnAuthoritativeIndex() async throws {
        let source = "# Target\n"
        let document = try await ParseEngine().parse(source, revision: 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await HeadingAnchorPreparation.prepare(
                document: document, sourceText: source, documentID: "own", recoveryEpoch: UUID(), sourceGeneration: 1
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func prepare(_ source: String) async throws -> HeadingAnchorPreparation {
        let document = try await ParseEngine().parse(source, revision: 1)
        return try await HeadingAnchorPreparation.prepare(
            document: document, sourceText: source, documentID: "own", recoveryEpoch: UUID(), sourceGeneration: 1
        )
    }
}
