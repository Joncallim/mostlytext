import Contributions
import DiagramsGraphviz
import DiagramWebKitPool
import Foundation
import GraphvizRendering
import JavaScriptCore
import MarkdownEngine
import OSLog
import Security

/// One disposable same-thread VM inside the already deadline-bound child.
/// The only input bridge is a bounded DOT string; no file or network API is
/// exposed to JavaScript. Publication still goes through the passive composer.
@MainActor
enum QuickLookGraphvizJSC {
    private static let logger = Logger(subsystem: "app.mostlytext.quicklook.worker", category: "graphviz-jsc")
    private static let maximumSVGBytes = GraphvizWebRenderer.defaultMaxOutputBytes

    static func render(
        document: MarkdownDocument, sourceText: String, generation: UInt, publishDeadline: Double,
        onAccepted: @MainActor ([ContributionResult]) -> Void
    ) -> [ContributionResult] {
        let fences = GraphvizFenceScanner.scan(document, sourceText: sourceText).filter {
            DiagramSourceBudget.byteCountIfOversized($0.source) == nil
        }
        guard !fences.isEmpty, let (context, deadline) = readyContext(publishDeadline: publishDeadline) else {
            return []
        }
        return renderFences(
            fences, context: context, deadline: deadline, generation: generation, onAccepted: onAccepted
        )
    }

    private static func readyContext(publishDeadline: Double) -> (JSContext, Double)? {
        let started = ProcessInfo.processInfo.systemUptime
        // Leave time for passive composition and the derived-completion marker.
        let deadline = min(started + 2.25, publishDeadline - 0.25)
        guard started < deadline else { return nil }
        guard let context = JSContext(), let script = try? GraphvizBundledScript.read() else {
            logger.error("JavaScriptCore context or pinned asset unavailable")
            return nil
        }
        installPureRuntimeHelpers(in: context)
        guard context.exception == nil else {
            logger.error("Pure JavaScriptCore runtime helpers failed")
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
        _ fences: [GraphvizFence], context: JSContext, deadline: Double, generation: UInt,
        onAccepted: @MainActor ([ContributionResult]) -> Void
    ) -> [ContributionResult] {
        var results: [ContributionResult] = []
        for fence in fences {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            context.setObject(fence.source, forKeyedSubscript: "__mostlyTextDot" as NSString)
            context.setObject(maximumSVGBytes, forKeyedSubscript: "__mostlyTextMaxSVGUnits" as NSString)
            let rendered = context.evaluateScript("""
            var __mostlyTextSVG = __mostlyTextViz.renderString(__mostlyTextDot, {
                format: 'svg',
                graphAttributes: { bgcolor: '#ffffff', fontname: 'Helvetica' },
                nodeAttributes: { fontname: 'Helvetica' },
                edgeAttributes: { fontname: 'Helvetica' }
            });
            typeof __mostlyTextSVG === 'string' && __mostlyTextSVG.length <= __mostlyTextMaxSVGUnits
                ? __mostlyTextSVG : null
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
            // A later synchronous layout may block until the child is killed.
            // Publish a complete snapshot after each accepted fence.
            onAccepted(results)
        }
        logger.notice("Graphviz rendered \(results.count) of \(fences.count) fences")
        return results
    }

    private static func state(_ context: JSContext) -> String {
        context.objectForKeyedSubscript("__mostlyTextVizState")?.toString() ?? "missing"
    }

    private static func installPureRuntimeHelpers(in context: JSContext) {
        let now: @convention(block) () -> Double = { ProcessInfo.processInfo.systemUptime }
        let decode: @convention(block) (NSArray) -> String = { values in
            let bytes = values.compactMap { ($0 as? NSNumber)?.uint8Value }
            return String(bytes: bytes, encoding: .utf8) ?? ""
        }
        let random: @convention(block) (Int) -> [NSNumber] = { count in
            guard (0 ... 65536).contains(count) else { return [] }
            var bytes = [UInt8](repeating: 0, count: count)
            guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { return [] }
            return bytes.map { NSNumber(value: $0) }
        }
        context.setObject(now, forKeyedSubscript: "__mostlyTextNow" as NSString)
        context.setObject(decode, forKeyedSubscript: "__mostlyTextDecode" as NSString)
        context.setObject(random, forKeyedSubscript: "__mostlyTextRandom" as NSString)
        context.evaluateScript("""
        globalThis.location = { href: 'file:///viz-global.js' };
        globalThis.console = { log() {}, error() {}, warn() {} };
        globalThis.performance = { now: () => __mostlyTextNow() * 1000 };
        globalThis.TextDecoder = class {
            constructor(label = 'utf-8') {
                if (!['utf-8', 'utf8'].includes(label.toLowerCase())) throw Error('Unsupported encoding');
            }
            decode(value = new Uint8Array()) {
                const bytes = value instanceof ArrayBuffer ? new Uint8Array(value)
                    : new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
                return __mostlyTextDecode(Array.from(bytes));
            }
        };
        globalThis.crypto = { getRandomValues(array) {
            if (!(array instanceof Uint8Array) || array.byteLength > 65536) throw Error('Random byte boundary');
            array.set(__mostlyTextRandom(array.byteLength));
            return array;
        } };
        """)
    }

    private static func svgFragment(_ output: String) -> String? {
        guard let start = output.range(of: "<svg"),
              let end = output.range(of: "</svg>", options: .backwards),
              start.lowerBound < end.lowerBound else { return nil }
        return String(output[start.lowerBound ..< end.upperBound])
    }
}
