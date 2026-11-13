import Contributions
import ExportService
import Foundation
import MarkdownEngine
import Math
import MathRendering
import QuickLookSource

/// Selected-source math path. The parent already owns a complete
/// source fallback; this method returns only a bounded derived candidate.
@MainActor
enum DerivedMathReply {
    static func render(_ source: String) async -> Data? {
        guard source.contains("$") else { return nil }
        do {
            let document = try await ParseEngine().parse(source, revision: 1)
            let context = ExportMathRenderContext(
                foregroundRed: 0.1, foregroundGreen: 0.1, foregroundBlue: 0.1,
                pixelScale: MathImageRenderer.standardScale
            )
            let contributor = SharedMathContribution(context: context) { body, style, context in
                try await MainActor.run {
                    try MathImageRenderer.render(body: body, style: style, context: context)
                }
            }
            let results = try await contributor.run(document: document, sourceText: source, sourceGeneration: 1)
            let items = results.compactMap(adapt)
            guard !items.isEmpty else { return nil }
            return QuickLookSourceFallback.replyHTML(
                forSource: source, contributions: items, sourceGeneration: 1
            )
        } catch {
            return nil
        }
    }

    private static func adapt(_ result: ContributionResult) -> ExportDerivedContribution? {
        guard let content = result.content else { return nil }
        let html: String
        switch content.representation {
        case let .html(fragment): html = fragment
        case .markdown: return nil
        }
        let placement: ExportDerivedPlacement = content.placement == .inline ? .inline : .block
        let diagnostics = result.diagnostics.map { item in
            ExportDiagnostic(
                severity: item.severity == .error ? .error : .warning,
                message: item.message, sourceRange: item.sourceRange,
                sourceID: item.sourceID, sourceOffset: item.sourceOffset,
                code: item.code, preventsPublication: item.preventsPublication
            )
        }
        return ExportDerivedContribution(
            sourceRange: content.sourceRange, placement: placement,
            html: html, sourceGeneration: result.sourceGeneration,
            diagnostics: diagnostics
        )
    }
}
