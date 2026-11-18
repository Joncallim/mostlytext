import Contributions
import DiagramsGraphviz
import DiagramWebKitPool
import Foundation
import GraphvizRendering
import JavaScriptCore
import MarkdownEngine
import OSLog

/// One disposable same-thread VM inside the already deadline-bound child.
/// The only input bridge is a bounded DOT string; no file or network API is
/// exposed to JavaScript. Publication still goes through the passive composer.
@MainActor
enum QuickLookGraphvizJSC {
    private static let logger = Logger(subsystem: "app.mostlytext.quicklook.worker", category: "graphviz-jsc")
    private static let maximumSVGBytes = GraphvizWebRenderer.defaultMaxOutputBytes

    static func render(document: MarkdownDocument, sourceText: String, generation: UInt) -> [ContributionResult] {
        let fences = GraphvizFenceScanner.scan(document, sourceText: sourceText)
        guard !fences.isEmpty, let (context, deadline) = readyContext() else { return [] }
        return renderFences(fences, context: context, deadline: deadline, generation: generation)
    }

    private static func readyContext() -> (JSContext, Double)? {
        let started = ProcessInfo.processInfo.systemUptime
        guard let context = JSContext(), let script = try? GraphvizBundledScript.read() else {
            logger.error("JavaScriptCore context or pinned asset unavailable")
            return nil
        }
        context.evaluateScript(script)
        guard context.exception == nil else {
            logger.error("Pinned Viz.js script evaluation failed")
            return nil
        }
        context.evaluateScript("""
        var __mostlyTextViz = null;
        var __mostlyTextVizState = 'pending';
        Viz.instance().then(function (value) {
            __mostlyTextViz = value;
            __mostlyTextVizState = 'ready';
        }, function () { __mostlyTextVizState = 'failed'; });
        """)
        guard context.exception == nil else {
            logger.error("Pinned Viz.js initialization threw")
            return nil
        }
        let deadline = started + 2.25
        while state(context) == "pending", ProcessInfo.processInfo.systemUptime < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
        guard state(context) == "ready" else {
            logger.error("Pinned Viz.js initialization did not settle within budget")
            return nil
        }
        logger.notice("Pinned Viz.js ready after \(ProcessInfo.processInfo.systemUptime - started) seconds")
        return (context, deadline)
    }

    private static func renderFences(
        _ fences: [GraphvizFence], context: JSContext, deadline: Double, generation: UInt
    ) -> [ContributionResult] {
        var results: [ContributionResult] = []
        for fence in fences {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            guard DiagramSourceBudget.byteCountIfOversized(fence.source) == nil else { continue }
            context.setObject(fence.source, forKeyedSubscript: "__mostlyTextDot" as NSString)
            let rendered = context.evaluateScript("""
            __mostlyTextViz.renderString(__mostlyTextDot, {
                format: 'svg',
                graphAttributes: { bgcolor: '#ffffff', fontname: 'Helvetica' },
                nodeAttributes: { fontname: 'Helvetica' },
                edgeAttributes: { fontname: 'Helvetica' }
            })
            """)
            guard context.exception == nil, let raw = rendered?.toString(),
                  raw.utf8.count <= maximumSVGBytes,
                  let svg = svgFragment(raw)
            else {
                logger.error("Pinned Viz.js render or SVG admission failed")
                context.exception = nil
                continue
            }
            results.append(ContributionResult(
                contributionID: "graphviz", content: ContributionContent(
                    sourceRange: fence.sourceRange, placement: .block, representation: .html(svg)
                ), sourceGeneration: generation
            ))
        }
        logger.notice("Graphviz rendered \(results.count) of \(fences.count) fences")
        return results
    }

    private static func state(_ context: JSContext) -> String {
        context.objectForKeyedSubscript("__mostlyTextVizState")?.toString() ?? "missing"
    }

    private static func svgFragment(_ output: String) -> String? {
        guard let start = output.range(of: "<svg"),
              let end = output.range(of: "</svg>", options: .backwards),
              start.lowerBound < end.lowerBound else { return nil }
        return String(output[start.lowerBound ..< end.upperBound])
    }
}
