import Contributions
import Foundation
@testable import MacDown2
import MarkdownEngine
import Preview
import Testing

@Suite("PreviewContributionAdapter")
struct PreviewContributionAdapterTests {
    /// A minimal `MarkdownDocument` sufficient for `compose(...)` tests:
    /// only `sourceMap` is read by the admission/composition pipeline —
    /// `base: [PreviewBlock]` carries the block shape independently.
    static func document(text: String) -> MarkdownDocument {
        MarkdownDocument(
            body: text, bodyLineOffset: 0, blocks: [], headings: [], frontMatter: nil,
            sourceMap: SourceMap(text: text), revision: 0, options: .default
        )
    }

    // MARK: - results

    @Test func resultsIsEmptyWithoutADocumentOrText() async throws {
        let withoutDocument = try await PreviewContributionAdapter.results(document: nil, text: "[TOC]", generation: 0)
        #expect(withoutDocument.isEmpty)

        let document = try await ParseEngine().parse("[TOC]", revision: 0)
        let withoutText = try await PreviewContributionAdapter.results(document: document, text: nil, generation: 0)
        #expect(withoutText.isEmpty)
    }

    @Test func resultsRunsTheStandardRegistryEndToEnd() async throws {
        let text = "# Title\n\n[TOC]\n\n## Section\n"
        let document = try await ParseEngine().parse(text, revision: 0)

        let results = try await PreviewContributionAdapter.results(document: document, text: text, generation: 3)

        #expect(results.count == 1)
        #expect(results.first?.content != nil)
        #expect(results.first?.sourceGeneration == 3)
    }

    @Test func adapterDiagnosticsFollowTheSelectedLanguageWithoutChangingSource() async throws {
        let text = "[TOC]"
        let document = try await ParseEngine().parse(text, revision: 0)
        let base = PreviewBlock.blocks(from: document, text: text)
        let content = ContributionContent(sourceRange: 0 ..< text.utf16.count,
                                          placement: .block, representation: .markdown("- derived"))
        let stale = ContributionResult(contributionID: "toc", content: content, sourceGeneration: 2)
        let french = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: [stale],
            sourceGeneration: 1, locale: Locale(identifier: "fr")
        )
        let english = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: [stale],
            sourceGeneration: 1, locale: Locale(identifier: "en")
        )

        #expect(french.blocks == base)
        #expect(english.blocks == base)
        #expect(french.diagnostics.first?.message.contains("n'est plus à jour") == true)
        #expect(english.diagnostics.first?.message.contains("is stale") == true)
        let identity = UUID()
        #expect(PreviewContributionTaskID(documentIdentity: identity, parsedRevision: 0,
                                          localeIdentifier: "fr") !=
                PreviewContributionTaskID(documentIdentity: identity, parsedRevision: 0,
                                          localeIdentifier: "en"))
    }

    // MARK: - compose: pass-through

    @Test func composeReturnsBaseUnchangedWithNoContributions() async throws {
        let text = "Hello\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let base = PreviewBlock.blocks(from: document, text: text)

        let composition = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: [], sourceGeneration: 0
        )

        #expect(composition.blocks == base)
        #expect(composition.diagnostics.isEmpty)
    }

    // MARK: - compose: paragraph splice (architecture pass 2/10)

    @Test func composePreservesAuthoredTextBeforeAndAfterAMarkerInOneParagraph() async throws {
        let text = "before\n[TOC]\nafter\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let base = PreviewBlock.blocks(from: document, text: text)
        #expect(base.count == 1)

        let results = try await ContributionRegistry.standard.run(
            document: document,
            sourceText: text,
            sourceGeneration: 1
        )
        let composition = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: results, sourceGeneration: 1
        )

        let blocks = try #require(composition.blocks)
        #expect(blocks.count == 3)
        // The authored prefix is the exact captured UTF-16 slice up to the
        // marker line's start, which includes line 1's own line terminator —
        // "never reconstruct... by joining logical lines" (architecture
        // takeover, "Source-ordered block composition").
        #expect(blocks[0].source == "before\n")
        #expect(blocks[1].kind == .custom("toc"))
        #expect(blocks[2].source == "after")
        #expect(composition.diagnostics.isEmpty)
    }

    @Test func composeHandlesCRLFEquivalently() async throws {
        let text = "before\r\n[TOC]\r\nafter\r\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let base = PreviewBlock.blocks(from: document, text: text)

        let results = try await ContributionRegistry.standard.run(
            document: document,
            sourceText: text,
            sourceGeneration: 1
        )
        let composition = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: results, sourceGeneration: 1
        )

        let blocks = try #require(composition.blocks)
        #expect(blocks.count == 3)
        // The authored prefix keeps its own CRLF; the marker line's whole CRLF
        // terminator is consumed with the placement, and the following line's
        // CRLF is not part of its (SourceMap) line range.
        #expect(blocks[0].source == "before\r\n")
        #expect(blocks[2].source == "after")
    }

    @Test func composeRespectsUTF16OffsetsAroundNonBMPText() async throws {
        let text = "🎉before\n[TOC]\nafter🎉\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let base = PreviewBlock.blocks(from: document, text: text)

        let results = try await ContributionRegistry.standard.run(
            document: document,
            sourceText: text,
            sourceGeneration: 1
        )
        let composition = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: results, sourceGeneration: 1
        )

        let blocks = try #require(composition.blocks)
        #expect(blocks[0].source == "🎉before\n")
        #expect(blocks[2].source == "after🎉")
    }

    @Test func composeLeavesUntouchedNeighboringBlocksByteForByte() async throws {
        let text = "# Title\n\n[TOC]\n\n## Section\n\nBody text.\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let base = PreviewBlock.blocks(from: document, text: text)

        let results = try await ContributionRegistry.standard.run(
            document: document,
            sourceText: text,
            sourceGeneration: 1
        )
        let composition = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: results, sourceGeneration: 1
        )

        let blocks = try #require(composition.blocks)
        let title = try #require(base.first { $0.source == "# Title" })
        let section = try #require(base.first { $0.source == "## Section" })
        let bodyText = try #require(base.first { $0.source == "Body text." })
        #expect(blocks.contains(title))
        #expect(blocks.contains(section))
        #expect(blocks.contains(bodyText))
    }

    @Test func composeIsDeterministicAcrossRepeatedCalls() async throws {
        let text = "before\n[TOC]\nafter\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let base = PreviewBlock.blocks(from: document, text: text)
        let results = try await ContributionRegistry.standard.run(
            document: document,
            sourceText: text,
            sourceGeneration: 1
        )

        let first = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: results, sourceGeneration: 1
        )
        let second = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: results, sourceGeneration: 1
        )

        #expect(first.blocks == second.blocks)
    }

    // MARK: - compose: generation / representation gating

    @Test func composeRejectsAStaleGeneration() async throws {
        let text = "[TOC]\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let base = PreviewBlock.blocks(from: document, text: text)
        let results = try await ContributionRegistry.standard.run(
            document: document,
            sourceText: text,
            sourceGeneration: 1
        )

        let composition = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: results, sourceGeneration: 2
        )

        #expect(composition.blocks == base)
        #expect(composition.diagnostics.contains { $0.severity == .error })
    }

    @Test func composeRejectsAnHTMLRepresentationWithADiagnostic() {
        let text = "[TOC]\n"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let content = ContributionContent(sourceRange: 0 ..< 5, placement: .block, representation: .html("<p>x</p>"))
        let result = ContributionResult(contributionID: "toc", content: content, sourceGeneration: 1)
        let document = Self.document(text: text)

        let composition = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: [result], sourceGeneration: 1
        )

        #expect(composition.blocks == base)
        #expect(composition.diagnostics.contains { $0.severity == .error })
    }

    @Test func composePreservesADiagnosticOnlyResultWithNoContent() {
        let text = "Body.\n"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let result = ContributionResult(
            contributionID: "broken", content: nil, sourceGeneration: 0,
            diagnostics: [ContributionDiagnostic(severity: .warning, message: "heads up")]
        )
        let document = Self.document(text: text)

        let composition = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: [result], sourceGeneration: 0
        )

        #expect(composition.blocks == base)
        #expect(composition.diagnostics == [
            PreviewContributionDiagnostic(contributionID: "broken", severity: .warning, message: "heads up"),
        ])
    }

    @Test func composeBlocksContentBearingResultCarryingAnErrorDiagnostic() {
        let text = "[TOC]\n"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let content = ContributionContent(sourceRange: 0 ..< 5, placement: .block, representation: .markdown("- x"))
        let result = ContributionResult(
            contributionID: "toc", content: content, sourceGeneration: 1,
            diagnostics: [ContributionDiagnostic(severity: .error, message: "renderer failed")]
        )
        let document = Self.document(text: text)

        let composition = PreviewContributionAdapter.compose(
            base: base, document: document, sourceText: text, contributions: [result], sourceGeneration: 1
        )

        #expect(composition.blocks == base)
        #expect(composition.diagnostics == [
            PreviewContributionDiagnostic(contributionID: "toc", severity: .error, message: "renderer failed"),
        ])
    }
}
