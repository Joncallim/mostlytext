import AppKit
import DiagramsGraphviz
import SwiftUI

/// Renders one ```dot```/```graphviz``` fence's diagram inline in the
/// native preview (epic-21-implementation.md §3.5, §5 Slice 4). Mirrors
/// `D2DiagramBlockView` exactly: displays `RenderedGraphvizDiagram.svg`
/// directly via `NSImage(data:)`, no raster snapshot needed.
struct GraphvizDiagramBlockView: View {
    let source: String
    let context: GraphvizRenderContext
    let renderer: any GraphvizDiagramRendering

    private enum RenderState {
        case loading
        case rendered(NSImage, width: Double, height: Double, svg: String)
        case failed(String)
    }

    @State private var renderState: RenderState = .loading

    var body: some View {
        Group {
            switch renderState {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                    .accessibilityIdentifier("graphvizDiagramLoading")
            case let .rendered(image, width, height, svg):
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(width, 640), maxHeight: height)
                    .accessibilityLabel(Text(verbatim: source))
                    .accessibilityIdentifier("graphvizDiagramImage")
                    .contextMenu {
                        Button("Copy as SVG") {
                            DiagramClipboard.copySVG(svg)
                        }
                        .accessibilityIdentifier("graphvizDiagramCopyAsSVG")
                    }
            case let .failed(message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("This diagram could not be rendered.")
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.1))
                .accessibilityIdentifier("graphvizDiagramError")
                .help(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: [source, context.fingerprint]) {
            await render()
        }
    }

    private func render() async {
        let fence = GraphvizFence(source: source, sourceRange: 0 ..< 0)
        do {
            let diagram = try await renderer.render(fence, context: context)
            guard !Task.isCancelled else { return }
            guard let svgData = diagram.svg.data(using: .utf8), let image = NSImage(data: svgData) else {
                renderState = .failed(DiagramFailurePresentation.noPreviewImage.message())
                return
            }
            renderState = .rendered(image, width: diagram.naturalWidth, height: diagram.naturalHeight, svg: diagram.svg)
        } catch {
            guard !Task.isCancelled else { return }
            renderState = .failed(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let renderError = error as? GraphvizRenderError else {
            return error.localizedDescription
        }
        switch renderError {
        case let .invalidSyntax(message): return message
        case .timedOut: return DiagramFailurePresentation.timedOut.message()
        case let .outputTooLarge(byteCount):
            return DiagramFailurePresentation.outputTooLarge(byteCount: byteCount).message()
        case .rendererUnavailable: return DiagramFailurePresentation.rendererUnavailable.message()
        }
    }
}
