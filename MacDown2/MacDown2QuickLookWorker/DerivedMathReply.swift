import Contributions
import DiagramsGraphviz
import ExportService
import Foundation
import GraphvizRendering
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
    static func render(_ source: String) async -> Data? {
        guard source.contains("$") || source.contains("```") || source.contains("~~~") else { return nil }
        do {
            let document = try await ParseEngine().parse(source, revision: 1)
            var results: [ContributionResult] = []
            if source.contains("$") {
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
            }
            if !GraphvizFenceScanner.scan(document, sourceText: source).isEmpty {
                let renderer = GraphvizWebRenderer(poolSize: 1, timeout: .seconds(2))
                let contributor = GraphvizContribution(
                    context: .neutralLight, renderer: LoggedGraphvizRenderer(base: renderer)
                )
                let started = ProcessInfo.processInfo.systemUptime
                let diagrams = try await contributor.run(document: document, sourceText: source, sourceGeneration: 1)
                let contentCount = diagrams.filter { $0.content != nil }.count
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                derivedLogger
                    .notice("Graphviz contributions: \(diagrams.count), content: \(contentCount), elapsed: \(elapsed)")
                await renderer.shutdown()
                derivedLogger.notice("Graphviz renderer shutdown completed")
                results += diagrams
            }
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

private struct LoggedGraphvizRenderer: GraphvizDiagramRendering {
    let base: GraphvizWebRenderer

    func render(_ fence: GraphvizFence, context: GraphvizRenderContext) async throws -> RenderedGraphvizDiagram {
        do {
            return try await base.render(fence, context: context)
        } catch {
            let category = switch error as? GraphvizRenderError {
            case .invalidSyntax: "invalidSyntax"
            case .timedOut: "timedOut"
            case .sourceTooLarge: "sourceTooLarge"
            case .outputTooLarge: "outputTooLarge"
            case .rendererUnavailable: "rendererUnavailable"
            case nil: "other"
            }
            derivedLogger.error("Graphviz renderer failed: \(category)")
            throw error
        }
    }
}
