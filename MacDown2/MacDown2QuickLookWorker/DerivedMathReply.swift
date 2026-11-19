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
/// source fallback; each accepted snapshot is complete before a later renderer runs.
@MainActor
enum DerivedMathReply {
    static func render(
        _ source: String, publishDeadline: Double, onSnapshot: @MainActor (Data) -> Bool
    ) async {
        guard source.contains("$") || source.contains("```") || source.contains("~~~") else { return }
        do {
            let document = try await ParseEngine().parse(source, revision: 1)
            var mathResults: [ContributionResult] = []
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
                    mathResults = try await contributor.run(document: document, sourceText: source, sourceGeneration: 1)
                } catch {
                    // A failed equation keeps its source but must not suppress a valid diagram.
                    derivedLogger.error("Static math unavailable; preserving equation source")
                }
            }
            if !mathResults.isEmpty {
                // Publish a complete math snapshot before synchronous Graphviz work.
                // A killed child may still return this immutable snapshot.
                publishSnapshot(source: source, results: mathResults, onSnapshot: onSnapshot)
            }
            let completedMath = mathResults
            if !GraphvizFenceScanner.scan(document, sourceText: source).isEmpty {
                _ = QuickLookGraphvizJSC.render(
                    document: document, sourceText: source, generation: 1, publishDeadline: publishDeadline,
                    onAccepted: { diagrams in
                        publishSnapshot(source: source, results: completedMath + diagrams, onSnapshot: onSnapshot)
                    }
                )
            }
        } catch {
            return
        }
    }

    private static func publishSnapshot(
        source: String, results: [ContributionResult], onSnapshot: @MainActor (Data) -> Bool
    ) {
        let items = results.compactMap(adapt)
        guard !items.isEmpty else { return }
        guard let html = QuickLookSourceFallback.renderedReplyHTML(
            forSource: source, contributions: items, sourceGeneration: 1
        ) else {
            derivedLogger.notice("Passive composition refused; previous snapshot retained")
            return
        }
        guard onSnapshot(html) else {
            derivedLogger.notice("Derived reply exceeds publication budget; previous snapshot retained")
            return
        }
        let hasSVG = html.range(of: Data("<svg".utf8)) != nil
        derivedLogger.notice("Derived reply bytes: \(html.count), SVG present: \(hasSVG)")
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
