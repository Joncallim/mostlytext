import Contributions
import DiagramsGraphviz
import ExportService
import Foundation
import MarkdownEngine
import Math
import MathRendering
import OSLog
import QuickLookSource

private let derivedLogger = Logger(subsystem: "app.mostlytext.quicklook.worker", category: "derived")

/// Selected-source static math and Graphviz. The parent already owns a complete
/// source fallback; this method returns only a bounded derived candidate.
@MainActor
enum DerivedMathReply {
    static func render(
        _ source: String, publishDeadline: Double, onMathReady: @MainActor (Data) -> Void
    ) async -> Data? {
        guard source.contains("$") || source.contains("```") || source.contains("~~~") else { return nil }
        do {
            let document = try await ParseEngine().parse(source, revision: 1)
            var results: [ContributionResult] = []
            if source.contains("$") {
                do {
                    let context = ExportMathRenderContext(
                        foregroundRed: 0.1, foregroundGreen: 0.1, foregroundBlue: 0.1,
                        pixelScale: MathImageRenderer.standardScale
                    )
                    let contributor = SharedMathContribution(context: context) { body, style, context in
                        try await MainActor.run {
                            try MathImageRenderer.render(body: body, style: style, context: context)
                        }
                    }
                    results += try await contributor.run(document: document, sourceText: source, sourceGeneration: 1)
                } catch {
                    // A failed equation keeps its source but must not suppress a valid diagram.
                    derivedLogger.error("Static math unavailable; preserving equation source")
                }
            }
            let mathItems = results.compactMap(adapt)
            if !mathItems.isEmpty {
                let mathHTML = QuickLookSourceFallback.replyHTML(
                    forSource: source, contributions: mathItems, sourceGeneration: 1
                )
                // Publish a complete math snapshot before synchronous Graphviz work.
                // A killed child may still return this immutable snapshot.
                onMathReady(mathHTML)
            }
            var graphviz: [ContributionResult] = []
            if !GraphvizFenceScanner.scan(document, sourceText: source).isEmpty {
                graphviz = QuickLookGraphvizJSC.render(
                    document: document, sourceText: source, generation: 1, publishDeadline: publishDeadline
                )
            }
            guard !graphviz.isEmpty else { return nil }
            results += graphviz
            let items = results.compactMap(adapt)
            guard !items.isEmpty else { return nil }
            let html = QuickLookSourceFallback.replyHTML(
                forSource: source, contributions: items, sourceGeneration: 1
            )
            let hasSVG = html.range(of: Data("<svg".utf8)) != nil
            derivedLogger.notice("Derived reply bytes: \(html.count), SVG present: \(hasSVG)")
            return html
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
