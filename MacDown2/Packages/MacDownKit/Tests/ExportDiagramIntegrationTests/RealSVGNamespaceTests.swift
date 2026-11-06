import AppKit
import D2Rendering
@testable import DiagramRendering
import Diagrams
import DiagramsD2
import DiagramsGraphviz
@testable import ExportService
import Foundation
import GraphvizRendering
import Testing
import WebKit

@Suite("Real diagram SVG namespace compatibility")
struct RealSVGNamespaceTests {
    @Test @MainActor func ownedRendererOutputsRemainAdmissibleAndD2FallsBack() async throws {
        let graphviz = GraphvizWebRenderer()
        let dot = try await graphviz.render(
            GraphvizFence(source: "digraph { a -> b; b -> c; }", sourceRange: 0 ..< 28),
            context: GraphvizRenderContext(
                foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
                backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
            )
        )
        await graphviz.shutdown()

        let d2Renderer = D2WebRenderer()
        let d2Diagram = try await d2Renderer.render(
            D2Fence(source: "a -> b -> c", sourceRange: 0 ..< 11),
            context: D2RenderContext(
                foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
                backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
            )
        )
        await d2Renderer.shutdown()

        let mermaidRenderer = MermaidWebRenderer()
        let mermaid = try await mermaidRenderer.render(
            MermaidFence(source: "graph TD; A-->B;", sourceRange: 0 ..< 16),
            context: MermaidRenderContext(
                foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
                backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
            )
        )
        await mermaidRenderer.shutdown()

        let canvas = try await MermaidHarnessPage.make()
        defer { canvas.teardown() }

        try checkStrictD2Fallback(d2Diagram.svg)

        let outputs = [("Graphviz", dot.svg), ("Mermaid", mermaid.svg)]
        for (name, svg) in outputs {
            try await check(name: name, svg: svg, on: canvas)
        }
        try await checkInlineComposition(outputs.map(\.1) + [dot.svg])
        try await checkOrdinaryHeadingNamespaces(
            [("Graphviz", dot.svg), ("D2", d2Diagram.svg), ("Mermaid", mermaid.svg), ("D2 repeated", d2Diagram.svg)],
            on: canvas
        )
    }

    private func checkStrictD2Fallback(_ svg: String) throws {
        let d2Sanitized = DerivedHTMLSanitizer.sanitized(svg)
        #expect(SVGIDNamespace.rewrite(d2Sanitized, occurrence: 0) == nil)
        // This D2 fixture emits a paint URL without a matching local ID. The
        // opt-in path retains the authored fence until renderer output can
        // meet the same ownership rule as Graphviz and Mermaid.
        let source = "```d2\na -> b -> c\n```\n"
        let d2Contribution = ExportDerivedContribution(
            sourceRange: 0 ..< source.utf16.count, placement: .block,
            html: svg, sourceGeneration: 1
        )
        let fallback = DerivedContentComposer.compose(
            bodyText: source, bodyStartOffset: 0, sourceUTF16Length: source.utf16.count,
            contributions: [d2Contribution], sourceGeneration: 1, namespaceSVGIDs: true
        )
        #expect(fallback.splicedBody == source)
        #expect(fallback.customNodes.isEmpty)
        #expect(fallback.diagnostics.contains { $0.severity == .error })
    }

    @MainActor private func check(name: String, svg: String, on canvas: MermaidHarnessPage) async throws {
        let sanitized = DerivedHTMLSanitizer.sanitized(svg)
        let rewritten = try #require(SVGIDNamespace.rewrite(sanitized, occurrence: 0))
        if let directory = ProcessInfo.processInfo.environment["MOSTLYTEXT_117_FIXTURE_DIR"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try svg.write(to: folder.appending(path: "\(name).svg"), atomically: true, encoding: .utf8)
            try sanitized.write(to: folder.appending(path: "\(name)-sanitized.svg"),
                                atomically: true, encoding: .utf8)
        }
        print("#117 real \(name): source=\(svg.utf8.count)B sanitized=\(sanitized.utf8.count)B "
            + "namespaced=\(rewritten.utf8.count)B")
        let originalIDs = try ids(in: sanitized)
        let rewrittenIDs = try ids(in: rewritten)
        #expect(!originalIDs.isEmpty)
        #expect(Set(rewrittenIDs).isSuperset(of: originalIDs.map { "mt117-svg-0-0-" + $0 }))
        let rootOpening = sanitized.split(separator: ">", maxSplits: 1).first ?? ""
        #expect(rewrittenIDs.count == originalIDs.count + (rootOpening.contains(" id=") ? 0 : 1))
        for id in originalIDs {
            if sanitized.contains("url(#\(id))") {
                #expect(rewritten.contains("url(#mt117-svg-0-0-\(id))"))
            }
            if sanitized.contains("href=\"#\(id)\"") {
                #expect(rewritten.contains("href=\"#mt117-svg-0-0-\(id)\""))
            }
        }
        let before = try await png(for: sanitized, on: canvas)
        let after = try await png(for: rewritten, on: canvas)
        #expect(before == after, "\(name) canvas pixels changed after ID namespacing")
    }

    private func ids(in svg: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_-])id="([^"]+)""#)
        let source = svg as NSString
        return expression.matches(in: svg, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range(at: 1)) }
    }

    @MainActor private func checkInlineComposition(_ outputs: [String]) async throws {
        let handler = RecordingResourceHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "resourceprobe")
        let view = WKWebView(frame: .init(x: 0, y: 0, width: 320, height: 200), configuration: configuration)
        var body = #"<svg id="graph0"><rect id="paint" style="fill:green"/></svg>"#
        for (index, svg) in outputs.enumerated() {
            let sanitized = DerivedHTMLSanitizer.sanitized(svg)
            let rewritten = try #require(SVGIDNamespace.rewrite(sanitized, occurrence: index))
            body += "<section class=\"diagram\">\(rewritten)</section>"
        }
        let html = BuiltInExportTemplate.document(
            title: "Mixed inline diagrams", styleElement: "<style></style>", body: body
        )
        view.loadHTMLString(html, baseURL: nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var count = 0
        while ContinuousClock.now < deadline {
            count = await (try? view.evaluateJavaScript("document.querySelectorAll('section.diagram > svg').length")
                as? Int) ?? 0
            if count == outputs.count {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(count == outputs.count)
        let script = """
        Array.from(document.querySelectorAll('section.diagram')).map((section, index) =>
          Array.from(section.querySelectorAll('[id]')).every(element =>
            element.id.startsWith(`mt117-svg-${index}-0-`))).every(Boolean)
        """
        #expect(try await view.evaluateJavaScript(script) as? Bool == true)
        #expect(handler.requests.isEmpty)
    }
}

@Suite("Assembled SVG resource admission", .serialized)
@MainActor
struct AssembledSVGResourceTests {
    @Test func outsideHeadCSSCanRedirectPaintThroughRuleOrInheritedVariable() async throws {
        let artwork = #"<svg id="root" width="48" height="48"><defs>"#
            + #"<linearGradient id="paint"><stop stop-color="red"/></linearGradient></defs>"#
            + #"<rect id="shape" width="48" height="48" fill="url(#paint)"/></svg>"#
        let marked = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        let outside = #"<svg width="0" height="0"><defs>"#
            + #"<linearGradient id="outside"><stop stop-color="blue"/></linearGradient>"#
            + #"</defs></svg>"#
        for css in [
            "svg rect { fill: url(#outside) }",
            ":root { --diagram-fill: url(#outside) } svg rect { fill: var(--diagram-fill) }",
        ] {
            let document = BuiltInExportTemplate.document(
                title: "Outside paint", styleElement: "<style>\(css)</style>", body: outside + marked.html
            )
            // This fails before outside-CSS admission is made fail-closed:
            // the syntactic SVG reference is owned, but browser CSS replaces it.
            #expect(SVGAssemblyOwnership.inspect(markedDocument: document, fragment: marked) == nil)

            let view = WKWebView(frame: .init(x: 0, y: 0, width: 80, height: 80))
            view.loadHTMLString(document, baseURL: nil)
            try await waitForLoad(in: view)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            var expectedDOMLoaded = false
            while ContinuousClock.now < deadline {
                expectedDOMLoaded = await (try? view.evaluateJavaScript(
                    "document.title === 'Outside paint' && document.querySelectorAll('svg rect').length === 1"
                ) as? Bool) == true
                if expectedDOMLoaded {
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(expectedDOMLoaded)
            let fill = try #require(try await view.evaluateJavaScript(
                "getComputedStyle(document.querySelector('svg rect')).fill"
            ) as? String)
            #expect(fill.contains("outside"))
            let image = try await view.takeSnapshot(configuration: nil)
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            var bluePixels = 0
            for pixelY in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                for pixelX in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                    guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB)
                    else { continue }
                    if color.blueComponent > color.redComponent + 0.2,
                       color.blueComponent > color.greenComponent + 0.2 {
                        bluePixels += 1
                    }
                }
            }
            #expect(bluePixels > 10)
        }
    }

    @Test func validatedPublishableHTMLKeepsOwnedPaintWithoutPrivateMarkers() async throws {
        let artwork = #"<svg id="root"><defs><linearGradient id="paint"/></defs>"#
            + #"<rect id="shape" fill="url(#paint)" width="20" height="20"/></svg>"#
        let marked = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        let assembled = BuiltInExportTemplate.document(
            title: "Owned paint", styleElement: "<style></style>", body: marked.html
        )
        let inspected = try #require(SVGAssemblyOwnership.inspect(markedDocument: assembled, fragment: marked))
        let publication = try #require(SVGAssemblyOwnership.publish(
            markedDocument: assembled, fragment: marked, inspected: inspected
        ))
        let handler = RecordingResourceHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "resourceprobe")
        let view = WKWebView(frame: .init(x: 0, y: 0, width: 80, height: 80), configuration: configuration)
        view.loadHTMLString(publication.html, baseURL: nil)
        try await waitForLoad(in: view)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if try await view.evaluateJavaScript("document.querySelectorAll('svg rect').length") as? Int == 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let script = """
        const rect = document.querySelector('svg rect');
        [rect?.id, rect?.getAttribute('fill'),
         document.documentElement.outerHTML.includes('MT117-SVG')].join('|')
        """
        let observed = try await view.evaluateJavaScript(script) as? String
        #expect(observed == "mt117-svg-0-0-shape|url(#mt117-svg-0-0-paint)|false")
        #expect(handler.requests.isEmpty)
    }

    @Test func validNegativeAnimationDelayKeepsItsComputedValue() async throws {
        let artwork = #"<svg id="root"><style>@keyframes pulse{to{opacity:1}}"#
            + #"#root rect{animation:pulse 1s -.5s linear}</style>"#
            + #"<rect width="20" height="20"/></svg>"#
        let rewritten = try #require(SVGIDNamespace.rewrite(artwork, occurrence: 0))
        let view = WKWebView(frame: .init(x: 0, y: 0, width: 50, height: 50))
        view.loadHTMLString(BuiltInExportTemplate.document(
            title: "Animation delay", styleElement: "<style></style>", body: rewritten
        ), baseURL: nil)
        try await waitForLoad(in: view)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            let count = try await view.evaluateJavaScript("document.querySelectorAll('svg rect').length") as? Int
            if count == 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let delay = try await view.evaluateJavaScript(
            "getComputedStyle(document.querySelector('svg rect')).animationDelay"
        ) as? String
        #expect(delay == "-0.5s")
    }

    @Test func repeatedInlineSVGsKeepStylesAndReferencesInsideTheirOwnOccurrence() async throws {
        let handler = RecordingResourceHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "resourceprobe")
        let view = WKWebView(frame: .init(x: 0, y: 0, width: 320, height: 200), configuration: configuration)
        let artwork = #"<svg id="root"><style>@keyframes pulse{from{opacity:0}to{opacity:1}}"#
            + #"#root rect{fill:red;animation:pulse 2s linear infinite}.scopeTarget{stroke:red}</style>"#
            + #"<rect id="shape" class="scopeTarget" width="20" height="20"/></svg>"#
        let different = #"<svg id="root"><style>@keyframes pulse{from{opacity:1}to{opacity:0}}"#
            + #"#root rect{fill:blue;animation:pulse 2s linear infinite}.scopeTarget{stroke:blue}</style>"#
            + #"<rect id="shape" class="scopeTarget" width="20" height="20"/></svg>"#
        let first = try #require(SVGIDNamespace.rewrite(artwork, occurrence: 0))
        let repeated = try #require(SVGIDNamespace.rewrite(artwork, occurrence: 1))
        let mixed = try #require(SVGIDNamespace.rewrite(different, occurrence: 2))
        let body = #"<svg id="root"><rect id="shape" class="scopeTarget" style="fill:green"/></svg>"#
            + "<div class=\"card\">\(first)</div><div class=\"card\">\(repeated)</div>"
            + "<div class=\"card\">\(mixed)</div>"
        let html = BuiltInExportTemplate.document(
            title: "Inline SVG isolation", styleElement: "<style></style>", body: body
        )
        view.loadHTMLString(html, baseURL: nil)
        try await waitForLoad(in: view)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let count = try? await view.evaluateJavaScript("document.querySelectorAll('.card svg').length") as? Int,
               count == 3 {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let script = """
        Array.from(document.querySelectorAll('.card svg')).map(svg => {
          const rect = svg.querySelector('rect');
          return [svg.id, rect.id, getComputedStyle(rect).fill].join(':');
        }).join('|')
        """
        let result = try #require(try await view.evaluateJavaScript(script) as? String)
        #expect(result == "mt117-svg-0-0-root:mt117-svg-0-0-shape:rgb(255, 0, 0)"
            + "|mt117-svg-1-0-root:mt117-svg-1-0-shape:rgb(255, 0, 0)"
            + "|mt117-svg-2-0-root:mt117-svg-2-0-shape:rgb(0, 0, 255)")
        #expect(handler.requests.isEmpty)
        let outsideStroke = try await view.evaluateJavaScript(
            "getComputedStyle(document.querySelector('body > svg rect')).stroke"
        ) as? String
        #expect(outsideStroke == "none")
        let animationNames = try await view.evaluateJavaScript(
            "Array.from(document.querySelectorAll('.card rect')).map(x => getComputedStyle(x).animationName).join('|')"
        ) as? String
        #expect(animationNames == "mt117-svg-0-0-pulse|mt117-svg-1-0-pulse|mt117-svg-2-0-pulse")
    }

    @Test func rejectedCSSNeverRequestsAResourceAfterInlineAssembly() async throws {
        let handler = RecordingResourceHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "resourceprobe")
        let view = WKWebView(frame: .init(x: 0, y: 0, width: 320, height: 200), configuration: configuration)

        for payload in [
            #"<svg id="g"><path fill="u\72l(resourceprobe://fixture/x.svg#g)"/></svg>"#,
            #"<svg id="g"><path style="fill:u&amp;#114;l(resourceprobe://fixture/x.svg#g)"/></svg>"#,
            #"<svg id="g"><style>@layer safe; @import url(resourceprobe://fixture/x.css) {#g{fill:red}}</style></svg>"#,
        ] {
            let html = try assembledHTML(for: payload)
            #expect(html.contains("<pre><code"))
            #expect(!html.contains("<svg"))
            view.loadHTMLString(html, baseURL: nil)
            try await waitForLoad(in: view)
            try await Task.sleep(for: .milliseconds(100))
            #expect(handler.requests.isEmpty)
        }

        // Prove this harness observes a subresource attempt without ever
        // touching an external network address.
        view.loadHTMLString(#"<img src="resourceprobe://fixture/control.png">"#, baseURL: nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while handler.requests.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(handler.requests.map(\.absoluteString) == ["resourceprobe://fixture/control.png"])
        view.stopLoading()
    }

    private func assembledHTML(for payload: String) throws -> String {
        let source = "```diagram\nsource\n```\n"
        let contribution = ExportDerivedContribution(
            sourceRange: 0 ..< source.utf16.count, placement: .block,
            html: payload, sourceGeneration: 1
        )
        let composed = DerivedContentComposer.compose(
            bodyText: source, bodyStartOffset: 0, sourceUTF16Length: source.utf16.count,
            contributions: [contribution], sourceGeneration: 1, namespaceSVGIDs: true
        )
        #expect(composed.splicedBody == source)
        #expect(composed.customNodes.isEmpty)
        let rendered = try CMarkGFM.render(composed.splicedBody, options: CMarkGFM.optUnsafe)
        return BuiltInExportTemplate.document(
            title: "Resource admission", styleElement: "<style></style>", body: rendered.html
        )
    }

    func waitForLoad(in view: WKWebView) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let state = try? await view.evaluateJavaScript("document.readyState") as? String,
               state == "complete" {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("WebKit did not finish the inline assembly fixture")
    }
}

@MainActor
final class RecordingResourceHandler: NSObject, WKURLSchemeHandler {
    private(set) var requests: [URL] = []

    func webView(_: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        requests.append(url)
        task.didReceive(URLResponse(url: url, mimeType: "image/png", expectedContentLength: 0,
                                    textEncodingName: nil))
        task.didReceive(Data())
        task.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}
