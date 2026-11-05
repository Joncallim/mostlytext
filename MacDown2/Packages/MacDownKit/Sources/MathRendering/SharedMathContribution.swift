import Contributions
import Foundation
import MarkdownEngine
import Math
import MathSyntax
import SwiftUIMath

/// Typed raster rendering is injected; recognition and parser validity cannot
/// be replaced by a separate dollar scanner or renderer error heuristic.
public typealias ValidatedMathImageRendering = @Sendable (
    SwiftUIMath.Math.ValidatedBody, MathDelimiterStyle, ExportMathRenderContext
) async throws -> RenderedMathImage

/// Export consumes the same exact-source analysis, bounded body and categories
/// as Preview. A failed rendering yields escaped authored source, never silent loss.
public struct SharedMathContribution: Contributing {
    public let id = "math"
    private let context: ExportMathRenderContext
    private let renderer: ValidatedMathImageRendering
    private let policy: MathProcessingPolicy
    private let budget: MathExportFragmentBudget

    private struct Source {
        let text: String
        let document: MarkdownDocument
        let generation: UInt
    }

    public init(context: ExportMathRenderContext, renderer: @escaping ValidatedMathImageRendering) {
        self.init(context: context, renderer: renderer, policy: .standard, budget: .standard)
    }

    init(context: ExportMathRenderContext, renderer: @escaping ValidatedMathImageRendering,
         policy: MathProcessingPolicy, budget: MathExportFragmentBudget) {
        self.context = context
        self.renderer = renderer
        self.policy = policy
        self.budget = budget
    }

    public func run(document: MarkdownDocument, sourceText: String,
                    sourceGeneration: UInt) async throws -> [ContributionResult] {
        let source = Source(text: sourceText, document: document, generation: sourceGeneration)
        do {
            let request = MathEvaluationRequest(
                source: sourceText, document: document, sourceIdentity: .init(rawValue: UUID()),
                generation: UInt64(sourceGeneration), maximumSpanCount: policy.maximumSpanCount,
                bodyLimits: policy.bodyLimits
            )
            let worker = MathEvaluationWorker()
            let outcome = await worker.submit(request)
            await worker.shutdown()
            try Task.checkCancellation()
            let evaluation: MathEvaluation
            switch outcome {
            case let .completed(value): evaluation = value
            case .cancelled, .superseded: throw CancellationError()
            case let .failed(error): throw error
            }
            let plan = try MathPresentationPlan(evaluation: evaluation, document: document)
            var builder = MathExportFragmentBuilder(budget: budget)
            var results: [ContributionResult] = []
            for entry in plan.entries {
                try Task.checkCancellation()
                try await results.append(result(for: entry, source: source, builder: &builder))
            }
            if let range = plan.literalRemainderRange, let sourceID = plan.literalRemainderID {
                let html = try builder.literal(source: sourceText, range: range)
                results.append(ContributionResult(
                    contributionID: id, content: .init(
                        sourceRange: range,
                        placement: .inline,
                        representation: .html(html)
                    ),
                    sourceGeneration: sourceGeneration, diagnostics: [
                        .init(
                            severity: .warning, message: MathDiagnosticText.remainder, sourceRange: range,
                            sourceID: sourceID, sourceOffset: range.lowerBound, code: "math.resourceLimit"
                        ),
                    ]
                ))
            }
            try Task.checkCancellation()
            return results
        } catch is CancellationError {
            throw CancellationError()
        } catch is MathExportFragmentBudget.Exhausted {
            return fatal(MathDiagnosticText.outputLimit, kind: .resourceLimit, generation: sourceGeneration)
        } catch {
            return fatal(MathDiagnosticText.analysisUnavailable, kind: .internalFailure, generation: sourceGeneration)
        }
    }

    private func result(for entry: MathEvaluation.Entry, source: Source,
                        builder: inout MathExportFragmentBuilder) async throws -> ContributionResult {
        switch entry.outcome {
        case let .rejected(problem):
            return try fallback(problem, equation: entry.equation, source: source, builder: &builder)
        case let .accepted(body):
            var problem: MathEquationDiagnostic?
            do {
                guard builder.budget.remainingHTMLBytes > 0 else { throw MathExportFragmentBudget.Exhausted() }
                guard builder.budget.pngBytes < builder.budget.maximumPNGBytes
                else { throw MathRenderError.resourceLimit }
                let image = try await renderer(body, entry.equation.syntax.style, context)
                try Task.checkCancellation()
                let html = try builder.image(image, alt: entry.equation.rendererExpression)
                return ContributionResult(
                    contributionID: id, content: .init(
                        sourceRange: entry.equation.syntax.fullRange,
                        placement: entry.equation.syntax.style == .inline ? .inline : .block,
                        representation: .html(html)
                    ), sourceGeneration: source.generation
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch is MathExportFragmentBudget.Exhausted {
                problem = renderingProblem(entry.equation, kind: .resourceLimit)
            } catch let error as MathRenderError {
                let kind = renderingKind(error)
                problem = renderingProblem(entry.equation, kind: kind)
            } catch {
                problem = renderingProblem(entry.equation, kind: .renderingFailed)
            }
            guard let problem else { throw MathRenderError.couldNotTypeset }
            return try fallback(problem, equation: entry.equation, source: source, builder: &builder)
        }
    }

    private func renderingKind(_ error: MathRenderError) -> MathEquationDiagnostic.Kind {
        switch error {
        case .noVisibleOutput: .noVisibleOutput
        case .resourceLimit: .resourceLimit
        case .couldNotTypeset, .invalidImageDimensions: .renderingFailed
        }
    }

    private func renderingProblem(_ equation: MathEquation,
                                  kind: MathEquationDiagnostic.Kind) -> MathEquationDiagnostic {
        .init(equationID: equation.id, kind: kind, sourceOffset: equation.syntax.bodyRange.lowerBound)
    }

    private func fallback(_ problem: MathEquationDiagnostic, equation: MathEquation, source: Source,
                          builder: inout MathExportFragmentBuilder) throws -> ContributionResult {
        let range = equation.syntax.fullRange
        let html = try builder.literal(source: source.text, range: range)
        let line = source.document.sourceMap.line(atUTF16Offset: problem.sourceOffset)
        let column = problem.sourceOffset - source.document.sourceMap.lineStartOffsets[line - 1] + 1
        let diagnostic = ContributionDiagnostic(
            severity: .warning, message: MathDiagnosticText.located(problem.kind, line: line, column: column),
            sourceRange: range, sourceID: equation.id, sourceOffset: problem.sourceOffset,
            code: "math." + problem.kind.rawValue
        )
        return ContributionResult(
            contributionID: id, content: .init(sourceRange: range, placement: .inline, representation: .html(html)),
            sourceGeneration: source.generation, diagnostics: [diagnostic]
        )
    }

    private func fatal(_ message: String, kind: MathEquationDiagnostic.Kind, generation: UInt) -> [ContributionResult] {
        let diagnostic = ContributionDiagnostic(
            severity: .error, message: message, code: "math." + kind.rawValue, preventsPublication: true
        )
        let result = ContributionResult(
            contributionID: id,
            content: nil,
            sourceGeneration: generation,
            diagnostics: [diagnostic]
        )
        return [result]
    }
}
