import Contributions
import Foundation
import MarkdownEngine

/// E20's Export-side producer, matching `MathContribution`'s exact shape
/// (epic-19-implementation.md, epic-20-implementation.md §2.1) and
/// registered alongside it for Export only — never for Preview
/// (epic-20-implementation.md §2.2 invariant): Preview's Mermaid rendering
/// goes through a dedicated native view (`MermaidDiagramBlockView`, app
/// target), not through `ContributionRegistry`, because
/// `PreviewContributionAdmission` rejects `.html` output for every
/// contribution, and this epic does not propose loosening that shared
/// guard for one consumer.
public struct MermaidContribution: Contributing {
    public let id = "mermaid"

    private let context: MermaidRenderContext
    private let renderer: any MermaidDiagramRendering

    public init(context: MermaidRenderContext, renderer: any MermaidDiagramRendering) {
        self.context = context
        self.renderer = renderer
    }

    /// For each ```mermaid``` fence found by `MermaidFenceScanner`: render it
    /// and contribute the raw `<svg>` markup via `.html` representation, or
    /// — on failure — contribute nothing for that fence and report an
    /// `.error` diagnostic, isolated from every other fence in the same
    /// document (epic-20-implementation.md §4, §9). A thrown
    /// `CancellationError` propagates immediately, abandoning remaining
    /// fences, matching `ContributionRegistry.run`'s own cancellation
    /// convention and `MathContribution.run`'s identical behavior.
    public func run(
        document: MarkdownDocument,
        sourceText: String,
        sourceGeneration: UInt
    ) async throws -> [ContributionResult] {
        var results: [ContributionResult] = []
        for fence in MermaidFenceScanner.scan(document, sourceText: sourceText) {
            try Task.checkCancellation()
            do {
                let diagram = try await renderer.render(fence, context: context)
                results.append(ContributionResult(
                    contributionID: id,
                    content: ContributionContent(
                        sourceRange: fence.sourceRange,
                        placement: .block,
                        representation: .html(diagram.svg)
                    ),
                    sourceGeneration: sourceGeneration
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                results.append(ContributionResult(
                    contributionID: id,
                    content: nil,
                    sourceGeneration: sourceGeneration,
                    diagnostics: [
                        ContributionDiagnostic(
                            severity: .error,
                            message: String(
                                localized: "diagram could not be rendered: \(Self.describe(error))",
                                bundle: .module
                            )
                        ),
                    ]
                ))
            }
        }
        return results
    }

    private static func describe(_ error: Error) -> String {
        guard let renderError = error as? MermaidRenderError else {
            return error.localizedDescription
        }
        switch renderError {
        case let .invalidSyntax(message): return message
        case .timedOut: return String(localized: "rendering timed out", bundle: .module)
        case .sourceTooLarge: return String(localized: "diagram source too large", bundle: .module)
        case let .outputTooLarge(byteCount):
            return String(localized: "rendered output too large (\(byteCount) bytes)", bundle: .module)
        case .rendererUnavailable: return String(localized: "renderer unavailable", bundle: .module)
        }
    }
}
