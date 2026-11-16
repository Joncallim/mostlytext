import Contributions
import Foundation
import MarkdownEngine

/// E21's Export-side producer for D2, matching `MermaidContribution`'s
/// exact shape — Export only, never Preview (epic-21-implementation.md
/// §2, §3.6).
public struct D2Contribution: Contributing {
    public let id = "d2"

    private let context: D2RenderContext
    private let renderer: any D2DiagramRendering

    public init(context: D2RenderContext, renderer: any D2DiagramRendering) {
        self.context = context
        self.renderer = renderer
    }

    public func run(
        document: MarkdownDocument,
        sourceText: String,
        sourceGeneration: UInt
    ) async throws -> [ContributionResult] {
        var results: [ContributionResult] = []
        for fence in D2FenceScanner.scan(document, sourceText: sourceText) {
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
        guard let renderError = error as? D2RenderError else {
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
