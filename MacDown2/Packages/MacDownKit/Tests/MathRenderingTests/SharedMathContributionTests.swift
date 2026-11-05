import Contributions
import Foundation
import MarkdownEngine
import Math
@testable import MathRendering
import MathSyntax
import SwiftUIMath
import Testing

@Suite("Shared source grammar and typed Export production")
struct SharedMathContributionTests {
    private actor Calls {
        var bodies: [Data] = []
        func record(_ source: String) {
            bodies.append(Data(source.utf8))
        }
    }

    private var context: ExportMathRenderContext {
        .init(foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0, pixelScale: 2)
    }

    private static var image: RenderedMathImage {
        .init(pngData: Data([0, 1, 2, 3]), logicalWidth: 20, logicalHeight: 12)
    }

    private func html(_ result: ContributionResult) throws -> String {
        let content = try #require(result.content)
        guard case let .html(value) = content.representation else {
            Issue.record("Typed math must provide its safe image or escaped source, not a second Markdown parse")
            return ""
        }
        return value
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func rendererReceivesTheActualSharedBodyWithoutCommentOrDelimiterRewriting(_ ending: String) async throws {
        let source = "---\ntitle: $data$\n---\n\n# **[$x$][]**\n\n[$x$]: /target\n\n" +
            "`$literal$` ![img $not$](/image)\n\n$$a % keep\n+b$$\n\n$\\$x$"
        let exactSource = source.replacingOccurrences(of: "\n", with: ending)
        let document = try await ParseEngine().parse(exactSource, revision: 7)
        let analysis = try MathAnalysis.analyze(source: exactSource, document: document,
                                                sourceIdentity: .init(rawValue: UUID()), maximumSpanCount: 512)
        #expect(analysis.equations.map(\.rendererExpression).map { Data($0.utf8) } == [
            Data("x".utf8), Data(("a % keep" + ending + "+b").utf8), Data("\\$x".utf8),
        ])
        let calls = Calls()
        let producer = SharedMathContribution(context: context) { body, _, _ in
            await calls.record(body.source)
            #expect(body.limits == MathProcessingPolicy.standard.bodyLimits)
            return Self.image
        }
        let results = try await producer.run(document: document, sourceText: exactSource, sourceGeneration: 7)
        #expect(await calls.bodies == analysis.equations.map { Data($0.rendererExpression.utf8) })
        #expect(results.map { $0.content?.sourceRange } == analysis.equations.map { Optional($0.syntax.fullRange) })
        #expect(results.allSatisfy { $0.diagnostics.isEmpty && $0.sourceGeneration == 7 })
        #expect(try results.map(html).allSatisfy { $0.hasPrefix("<img src=\"data:image/png;base64,") })
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func malformedBodyHasItsOwnMappedSourceAndReadableFallbackBetweenValidNeighbors(_ ending: String) async throws {
        let source = "$x$\n\n> $$a % keep\n> \\unknown$$\n\n$y$".replacingOccurrences(of: "\n", with: ending)
        let document = try await ParseEngine().parse(source, revision: 1)
        let calls = Calls()
        let producer = SharedMathContribution(context: context) { body, _, _ in
            await calls.record(body.source)
            return Self.image
        }
        let results = try await producer.run(document: document, sourceText: source, sourceGeneration: 9)
        try #require(results.count == 3)
        #expect(await calls.bodies == [Data("x".utf8), Data("y".utf8)])
        let problem = try #require(results[1].diagnostics.first)
        #expect(problem.code == "math.unrecognizedCommand")
        #expect(problem.severity == .warning && !problem.preventsPublication)
        #expect(problem.sourceID != nil && problem.sourceRange == results[1].content?.sourceRange)
        let offset = try #require(problem.sourceOffset)
        #expect(document.sourceMap.line(atUTF16Offset: offset) == 4)
        let range = try #require(problem.sourceRange)
        #expect(range.contains(offset) || range.upperBound == offset)
        let fallback = try html(results[1])
        #expect(fallback.contains("$" + "$a % keep" + ending + "&gt; \\unknown$$"))
        #expect(!fallback.contains("<img"))
        #expect(results[0].diagnostics.isEmpty && results[2].diagnostics.isEmpty)
    }

    @Test func validNoInkAndActualRendererFailuresRetainDifferentCategories() async throws {
        let source = "$$\n$$\n\n$$% comment\n$$\n\n$$\\ $$\n\n$x$"
        let document = try await ParseEngine().parse(source, revision: 1)
        let calls = Calls()
        let producer = SharedMathContribution(context: context) { body, _, _ in
            await calls.record(body.source)
            if body.source == "x" {
                throw MathRenderError.couldNotTypeset
            }
            throw MathRenderError.noVisibleOutput
        }
        let results = try await producer.run(document: document, sourceText: source, sourceGeneration: 1)
        #expect(await calls.bodies.count == 4)
        #expect(results.compactMap { $0.diagnostics.first?.code } == [
            "math.noVisibleOutput", "math.noVisibleOutput", "math.noVisibleOutput", "math.renderingFailed",
        ])
        #expect(try results.map(html).allSatisfy { $0.contains("math-source-fallback") })
        #expect(results.flatMap(\.diagnostics).allSatisfy { !$0.preventsPublication && $0.sourceID != nil })
    }

    @Test func noRasterAllowanceAvoidsTheRendererAndPreservesSource() async throws {
        let source = "$x$"
        let document = try await ParseEngine().parse(source, revision: 1)
        let calls = Calls()
        let producer = SharedMathContribution(context: context, renderer: { body, _, _ in
            await calls.record(body.source)
            return Self.image
        }, policy: .standard, budget: .init(maximumPNGBytes: 0, maximumHTMLBytes: 1024))
        let results = try await producer.run(document: document, sourceText: source, sourceGeneration: 1)
        #expect(await calls.bodies.isEmpty)
        #expect(results.first?.diagnostics.first?.code == "math.resourceLimit")
        #expect(try html(#require(results.first)).contains("$x$"))
    }

    @Test func aggregateFailureDiscardsAnAlreadyPreparedEquationInsteadOfPublishingPartialMath() async throws {
        let source = "$x$ then $y$"
        let document = try await ParseEngine().parse(source, revision: 1)
        var measure = MathExportFragmentBuilder()
        let first = try measure.image(Self.image, alt: "x")
        let calls = Calls()
        let producer = SharedMathContribution(context: context, renderer: { body, _, _ in
            await calls.record(body.source)
            return Self.image
        }, policy: .standard, budget: .init(maximumPNGBytes: 100, maximumHTMLBytes: first.utf8.count))
        let results = try await producer.run(document: document, sourceText: source, sourceGeneration: 17)
        try #require(results.count == 1)
        #expect(results[0].content == nil && results[0].sourceGeneration == 17)
        #expect(results[0].diagnostics.first?.preventsPublication == true)
        #expect(results[0].diagnostics.first?.code == "math.resourceLimit")
        #expect(await calls.bodies == [Data("x".utf8)])
    }

    @Test func occurrenceCapHasOneSharedOriginalBlockBoundaryIncludingFrontMatter() async throws {
        let source = "---\ntitle: $data$\n---\n\n$x$\n\n$y$ $z$\n"
        let document = try await ParseEngine().parse(source, revision: 1)
        let policy = MathProcessingPolicy(maximumSpanCount: 2, bodyLimits: MathProcessingPolicy.standard.bodyLimits)
        let analysis = try MathAnalysis.analyze(source: source, document: document,
                                                sourceIdentity: .init(rawValue: UUID()),
                                                maximumSpanCount: policy.maximumSpanCount)
        let evaluation = try MathEvaluation.evaluate(analysis: analysis, limits: policy.bodyLimits)
        let plan = try MathPresentationPlan(evaluation: evaluation, document: document)
        #expect(plan.entries.map(\.equation.rendererExpression) == ["x"])
        let tail = try #require(plan.literalRemainderRange)
        #expect((source as NSString)
            .substring(with: .init(location: tail.lowerBound, length: tail.count)) == "$y$ $z$\n")
        let producer = SharedMathContribution(
            context: context,
            renderer: { _, _, _ in Self.image },
            policy: policy,
            budget: .standard
        )
        let results = try await producer.run(document: document, sourceText: source, sourceGeneration: 1)
        #expect(results.map { $0.content?.sourceRange } == [plan.entries.first?.equation.syntax.fullRange, tail])
        #expect(results.last?.diagnostics.first?.code == "math.resourceLimit")
        #expect(try html(#require(results.last)).contains("$y$ $z$\n"))
    }

    @Test func staleOriginalSourceCannotYieldEitherImagesOrAnUnprovenFallback() async throws {
        let original = "$x$"
        let document = try await ParseEngine().parse(original, revision: 1)
        let calls = Calls()
        let producer = SharedMathContribution(context: context) { body, _, _ in
            await calls.record(body.source)
            return Self.image
        }
        let results = try await producer.run(document: document, sourceText: "$y$", sourceGeneration: 1)
        #expect(await calls.bodies.isEmpty)
        #expect(results.count == 1 && results.first?.content == nil)
        #expect(results.first?.diagnostics.first?.preventsPublication == true)
        #expect(results.first?.diagnostics.first?.code == "math.internalFailure")
    }

    @Test func cancellationPropagatesInsteadOfReturningAnyFallback() async throws {
        let source = "$x$"
        let document = try await ParseEngine().parse(source, revision: 1)
        let producer = SharedMathContribution(context: context) { _, _, _ in throw CancellationError() }
        do {
            _ = try await producer.run(document: document, sourceText: source, sourceGeneration: 1)
            Issue.record("Cancellation must abandon the complete math result")
        } catch is CancellationError {
            // Expected; no content or misleading renderer diagnostic escaped.
        }
    }

    @Test func unmatchedQuadrupleDollarsStayAuthoredWithoutAMalformedClaim() async throws {
        let source = "$$$$"
        let document = try await ParseEngine().parse(source, revision: 1)
        let calls = Calls()
        let producer = SharedMathContribution(context: context) { body, _, _ in
            await calls.record(body.source)
            return Self.image
        }
        let results = try await producer.run(document: document, sourceText: source, sourceGeneration: 1)
        #expect(results.isEmpty)
        #expect(await calls.bodies.isEmpty)
    }
}
