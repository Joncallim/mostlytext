import Diagrams
import DiagramsD2
import DiagramsGraphviz
import Foundation
import MarkdownEngine
import Preview
import Testing

/// A source-boundary comparison. Native Preview and Export render diagrams
/// separately, but a top-level fence must feed both the same authored body.
/// Export's scanners also descend into list and quote children; Preview renders
/// only top-level code blocks as diagrams, so this does not claim nested parity.
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
