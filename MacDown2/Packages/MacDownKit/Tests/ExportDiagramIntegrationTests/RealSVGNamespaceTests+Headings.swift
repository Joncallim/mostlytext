import Contributions
@testable import DiagramRendering
@testable import ExportService
import Foundation
import MarkdownEngine
import Testing
import Themes
import WebKit

extension RealSVGNamespaceTests {
    @MainActor func checkOrdinaryHeadingNamespaces(
        _ outputs: [(String, String)], on canvas: MermaidHarnessPage
    ) async throws {
        let family = "MTTOC-SVG-1-"
        for (index, output) in outputs.enumerated() {
            let sanitized = DerivedHTMLSanitizer.sanitized(output.1)
            let rewritten = try #require(HeadingSVGNamespace.rewrite(sanitized, occurrence: index, family: family))
            let before = try await png(for: sanitized, on: canvas)
            let after = try await png(for: rewritten.html, on: canvas)
            #expect(before == after, "\(output.0) ordinary heading namespace changed canvas pixels")
        }
        for authoredAlias in [false, true] {
            try await checkNormalHeadingHTML(outputs, authoredAlias: authoredAlias)
        }
    }

    @MainActor private func checkNormalHeadingHTML(_ outputs: [(String, String)], authoredAlias: Bool) async throws {
        let html = try await ordinaryHeadingHTML(outputs, authoredAlias: authoredAlias)
        let handler = RecordingResourceHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "resourceprobe")
        let view = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 600), configuration: configuration)
        defer { view.stopLoading() }
        view.loadHTMLString(html, baseURL: nil)
        try await AssembledSVGResourceTests().waitForLoad(in: view)
        let observed = try await view.evaluateJavaScript("""
        (() => {
          const ids = Array.from(document.querySelectorAll('[id]')).map(x => x.id);
          const svgs = Array.from(document.querySelectorAll('svg'));
          const link = document.querySelector('a[href="#target"]');
          return svgs.length === 4 && new Set(ids).size === ids.length &&
            svgs.every(x => x.id.startsWith('\(authoredAlias ? "MTTOC-SVG-1-" : "MTTOC-SVG-0-")')) &&
            document.querySelectorAll('#target').length === 1 &&
            document.getElementById('target').tagName === 'H1' && link !== null &&
            (document.querySelector('a[name="MTTOC-SVG-0-authored"]') !== null) === \(authoredAlias ? "true" : "false");
        })()
        """) as? Bool
        #expect(
            observed == true,
            "Actual normal-template HTML must retain all mixed vector diagrams and one TOC target"
        )
        #expect(handler.requests.isEmpty)
    }

    private func ordinaryHeadingHTML(_ outputs: [(String, String)], authoredAlias: Bool) async throws -> String {
        let authored = authoredAlias ? "<a name='MTTOC-SVG-0-authored'></a>\n\n" : ""
        let source = "[TOC]\n\n# Target\n\n" + authored + outputs.indices.map { "```diagram\noccurrence \($0)\n```\n" }
            .joined(separator: "\n")
        let document = try await ParseEngine().parse(source, revision: 1)
        let preparation = try await HeadingAnchorPreparation.prepare(
            document: document, sourceText: source, documentID: "real-renderer-heading-test",
            recoveryEpoch: UUID(), sourceGeneration: 1
        )
        let results = try await TOCContribution(headingIndex: preparation.index).run(
            document: document, sourceText: source, sourceGeneration: 1
        )
        guard case let .markdown(list)? = results.first?.content?.representation else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let toc = ExportService.renderMarkdownFragment(list)
        var contributions = [placed("[TOC]", in: source, html: toc, required: true)]
        for (index, output) in outputs.enumerated() {
            contributions.append(placed("```diagram\noccurrence \(index)\n```", in: source, html: output.1))
        }
        let prepared = try await ExportService.prepare(
            .init(text: source, sourceGeneration: 1, theme: BundledThemes.light,
                  contributions: contributions, headingPreparation: preparation),
            target: .html(
                url: URL(fileURLWithPath: "/tmp/real-heading-diagrams.html"),
                mode: authoredAlias ? .standalone(style: .embedded) : .selfContained
            )
        )
        #expect(!prepared.diagnostics.contains { $0.severity == .error })
        #expect(!prepared.bodyHTML.contains("<pre><code"), "Every real diagram must remain vector SVG")
        return try authoredAlias
            ? ExportHTMLWriter.companionHTML(from: prepared, style: .embedded)
            : ExportHTMLWriter.selfContainedHTML(from: prepared)
    }

    private func placed(
        _ needle: String, in source: String, html: String, required: Bool = false
    ) -> ExportDerivedContribution {
        let range = (source as NSString).range(of: needle, options: .literal)
        return .init(sourceRange: range.location ..< NSMaxRange(range), placement: .block,
                     html: html, sourceGeneration: 1, requiresHeadingNavigation: required)
    }
}
