import Contributions
import Foundation
@testable import MacDown2
import MarkdownEngine
import Math
import MathRendering
import Preview
import Testing
import Textual
import Themes

/// Runs only in native hosted CI. Uses the real shared parser, native geometry,
/// typed attachment builder and production Export registry, without test renderers.
@MainActor
struct SharedMathActivationTests {
    struct GrammarCase: Sendable {
        let source: String
        let expressions: [String]
    }

    nonisolated static let grammar: [GrammarCase] = [
        .init(source: #"Prices $5 and $10; then \$literal and $x$. Even \\$y$; $z$2 and $ good$"#,
              expressions: ["x", "y"]),
        .init(source: #"Escaped \$x$ remains source; real $a\$b$ survives unchanged."#,
              expressions: [#"a\$b"#]),
        .init(source: "`$code$` ![alt $image$](/img) <https://example.com/$url$> and $x$",
              expressions: ["x"]),
        .init(source: "| A | B |\n|---|---|\n| $x$ | $y$ |", expressions: ["x", "y"]),
        .init(source: "> - $$a % unchanged comment\n>   +b$$", expressions: ["a % unchanged comment\n+b"]),
    ]

    private func request(_ source: String) async throws -> MathPreviewSourceRequest {
        let document = try await ParseEngine().parse(source, revision: 1)
        let analysis = try MathAnalysis.analyze(source: source, document: document,
                                                sourceIdentity: .init(rawValue: UUID()), maximumSpanCount: 512)
        let evaluation = try MathEvaluation.evaluate(
            analysis: analysis,
            limits: MathProcessingPolicy.standard.bodyLimits
        )
        return try .init(source: source, document: document, blocks: PreviewBlock.blocks(from: document, text: source),
                         evaluation: evaluation, presentation: MathPresentationPlan(evaluation: evaluation,
                                                                                    document: document))
    }

    @Test(arguments: grammar)
    func productionDestinationsUseTheSameOriginalDollarGrammar(_ fixture: GrammarCase) async throws {
        let request = try await request(fixture.source)
        #expect(request.evaluation.entries.map(\.equation.rendererExpression) == fixture.expressions)
        let display = try await MathPreviewDisplayBuilder.prepare(request, bindingID: UUID())
        #expect(display.notices.isEmpty)
        var nativeIDs = Set<UUID>()
        for block in request.blocks {
            guard case let .parsed(input)? = display.content.blocks[block.id] else {
                Issue.record("The parity corpus must pass native source-authority admission")
                continue
            }
            let native = try PreviewMathMarkupParser(input: input, attachments: display.content.attachments)
                .attributedString(for: block.source)
            for run in native.runs where run.textual.attachment != nil {
                try nativeIDs.insert(#require(run[PreviewMathSourceAttribute.self]))
            }
        }
        #expect(nativeIDs == Set(request.evaluation.entries.map(\.id)))
        let output = try await ContributionRegistry.standardForExport(theme: BundledThemes.light, isPrintTarget: false)
            .run(document: request.document, sourceText: fixture.source, sourceGeneration: 0)
            .filter { $0.contributionID == "math" }
        #expect(output.flatMap(\.diagnostics).isEmpty)
        #expect(output.compactMap { $0.content?.sourceRange } == request.evaluation.entries
            .map(\.equation.syntax.fullRange))
    }

    @Test func repeatedEquationsKeepDistinctOwnActionsWhileBothDestinationsAgreeOnFailures() async throws {
        let source = "First $x$ and second $x$.\n\nBad $\\unknowncommand$.\n\n$$\n$$"
        let request = try await request(source)
        #expect(request.evaluation.entries.count == 4)
        let display = try await MathPreviewDisplayBuilder.prepare(request, bindingID: UUID())
        let accepted = Array(request.evaluation.entries.prefix(2))
        #expect(display.content.attachments.count == 2)
        for entry in accepted {
            let attachment = try #require(display.content.attachments[entry.id])
            #expect(attachment.accessibility?.actionID == entry.id)
            #expect(attachment.accessibility?.actionName == MathDiagnosticText.sourceAction)
            #expect(attachment.accessibility?.label == MathDiagnosticText.equationLabel("x", isDisplay: false))
            #expect(display.locations[entry.id]?.range == entry.equation.syntax.fullRange)
        }
        #expect(Set(display.notices.map(\.kind)) == [.unrecognizedCommand, .noVisibleOutput])
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.light, isPrintTarget: false)
        let output = try await registry.run(document: request.document, sourceText: source, sourceGeneration: 0)
            .filter { $0.contributionID == "math" }
        #expect(output.count == 4)
        let diagnostics = output.flatMap(\.diagnostics)
        #expect(Set(diagnostics.compactMap(\.code)) == Set(display.notices.map { "math." + $0.kind.rawValue }))
        for notice in display.notices {
            let location = try #require(display.locations[notice.id])
            let matching = try #require(diagnostics.first { $0.sourceRange == location.range })
            #expect(matching.sourceOffset == location.diagnosticOffset)
            #expect(matching.message == notice.message)
            #expect(!matching.preventsPublication)
        }
        let adapted = ExportContributionAdapter.adapt(output, destination: .htmlExport)
        try adapted.requirePublication()
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func actualNativeReplayKeepsTheOriginalImplicitReferenceAndOwnAttachment(_ ending: String) async throws {
        let source = "> - [$x$][]\n\n[$x$]: /right \"own title\"".replacingOccurrences(of: "\n", with: ending)
        let request = try await request(source)
        let display = try await MathPreviewDisplayBuilder.prepare(request, bindingID: UUID())
        let block = try #require(request.blocks.first)
        let occurrence = try #require(request.evaluation.entries.first)
        guard case let .parsed(input)? = display.content.blocks[block.id] else {
            Issue.record("Expected original-source native input")
            return
        }
        let attributed = try PreviewMathMarkupParser(input: input, attachments: display.content.attachments)
            .attributedString(for: block.source)
        let run = try #require(attributed.runs.first { $0.textual.attachment != nil })
        #expect(run.link?.relativeString == "/right")
        #expect(run.textual.attachment?.accessibility?.actionID == occurrence.id)
        #expect(run[PreviewMathSourceAttribute.self] == occurrence.id)
        #expect(!String(attributed.characters).contains("MT_MATH"))
    }

    @Test func cancelledPreparationNeverCreatesAnAuthoritativeFrame() async throws {
        let request = try await request("$x$")
        let task = Task { try await MathPreviewDisplayBuilder.prepare(request, bindingID: UUID()) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func wholeAnalysisFailureShowsAuthoredBlocksWithoutInventingSourceActions() async throws {
        let request = try await request("$x$\n\n```\n$code$\n```")
        let display = MathPreviewDisplayBuilder.fallback(blocks: request.blocks, bindingID: UUID())
        #expect(display.content.attachments.isEmpty && display.locations.isEmpty)
        #expect(display.notices.count == 1 && display.notices.first?.sourceID == nil)
        for block in request.blocks {
            guard case .literal? = display.content.blocks[block.id] else {
                Issue.record("A failed whole-source analysis must show the authored block")
                continue
            }
        }
    }
}
