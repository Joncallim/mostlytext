import Diagrams
import DiagramsD2
import DiagramsGraphviz
import ExportService
import Foundation
import MarkdownEngine
import Preview
import Testing
import Themes

/// A source-boundary comparison. Native Preview and Export render diagrams
/// separately, but a top-level fence must feed both the same authored body.
/// Nested list/quote fences remain authored code in both paths. This checks the
/// source policy and container structure, not rendered visual or PDF parity.
@Suite("Preview and export diagram source parity")
struct PreviewDiagramSourceParityTests {
    private struct FenceSource {
        let body: String
        let range: Range<Int>
    }

    @Test(arguments: ["mermaid", "d2", "dot", "graphviz"])
    func topLevelFencesFeedBothPathsTheSameSource(language: String) async throws {
        for ending in ["\n", "\r\n", "\r"] {
            let prefix = "---\ntitle: Café 東京\n---\n\n# Before\n\n"
            let fence = "~~~\(language.uppercased())\(ending)a -> b\(ending)~~~"
            let source = prefix + fence + "\n\nAfter\n"
            let document = try await ParseEngine().parse(source, revision: 9)
            let previewBlocks = PreviewBlock.blocks(from: document, text: source)
            let previewFence = try #require(previewBlocks.first { block in
                if case let .codeBlock(tag) = block.kind {
                    return tag?.caseInsensitiveCompare(language) == .orderedSame
                }
                return false
            })
            let exportFence = try #require(scannedFences(language, document: document, source: source).first)

            #expect(document.isBound(to: source))
            #expect(!previewFence.isOversize)
            #expect(previewFence.source == fence)
            #expect(previewFence.sourceAnchor?.range == exportFence.range)
            #expect((source as NSString).substring(with: NSRange(
                location: exportFence.range.lowerBound, length: exportFence.range.count
            )) == fence)
            #expect(previewBody(language, from: previewFence.source) == exportFence.body)
            #expect(exportFence.body == "a -> b")
        }
    }

    @Test(arguments: ["mermaid", "d2", "dot", "graphviz"])
    func nestedFencesRemainSourceInsideTheirContainer(language: String) async throws {
        for (fence, expectedKind, containerTag) in [
            ("> ```\(language)\n> graph TD\n> ```", BlockKind.blockQuote, "blockquote"),
            ("- ```\(language)\n  graph TD\n  ```", BlockKind.unorderedList, "ul"),
        ] {
            let source = "# Café 🙂\n\n" + fence + "\n\nAfter\n"
            let document = try await ParseEngine().parse(source, revision: 10)
            let previewBlock = try #require(PreviewBlock.blocks(from: document, text: source)
                .first { $0.source.contains("graph TD") })
            let exportFence = try #require(scannedFences(language, document: document, source: source).first)
            let originalFence = (source as NSString).substring(with: NSRange(
                location: exportFence.range.lowerBound, length: exportFence.range.count
            ))

            #expect(previewBlock.kind == expectedKind)
            #expect(previewBlock.source.contains(fence))
            #expect(previewBlock.sourceAnchor?.range.contains(exportFence.range.lowerBound) == true)
            #expect(originalFence == fence)
            #expect(exportFence.body == "graph TD")

            // Even when a renderer supplies SVG for the parsed child fence,
            // the export composer keeps the list/quote intact and source readable.
            let contribution = ExportDerivedContribution(
                sourceRange: exportFence.range, placement: .block,
                html: "<svg>rendered</svg>", sourceGeneration: 10
            )
            let prepared = try await ExportService.prepare(
                ExportRequest(
                    text: source, sourceGeneration: 10, theme: BundledThemes.light,
                    contributions: [contribution]
                ),
                target: .html(url: URL(fileURLWithPath: "/tmp/nested-diagram-parity.html"),
                              mode: .standalone(style: .embedded))
            )
            #expect(prepared.bodyHTML.contains("<\(containerTag)>"))
            #expect(prepared.bodyHTML.contains("graph TD"))
            #expect(!prepared.bodyHTML.contains("<svg>rendered</svg>"))
            #expect(prepared.diagnostics.contains { $0.message.contains("list item or block quote") })
        }
    }

    private func previewBody(_ language: String, from fence: String) -> String {
        switch language {
        case "mermaid": MermaidFenceContent.stripDelimiters(from: fence)
        case "d2": D2FenceContent.stripDelimiters(from: fence)
        default: GraphvizFenceContent.stripDelimiters(from: fence)
        }
    }

    private func scannedFences(_ language: String, document: MarkdownDocument, source: String) -> [FenceSource] {
        switch language {
        case "mermaid": MermaidFenceScanner.scan(document, sourceText: source).map {
                FenceSource(body: $0.source, range: $0.sourceRange)
            }
        case "d2": D2FenceScanner.scan(document, sourceText: source).map {
                FenceSource(body: $0.source, range: $0.sourceRange)
            }
        default: GraphvizFenceScanner.scan(document, sourceText: source).map {
                FenceSource(body: $0.source, range: $0.sourceRange)
            }
        }
    }
}
