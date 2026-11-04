import AppKit
import DiagramsD2
import SwiftUI

/// Renders one ```d2``` fence's diagram inline in the native preview
/// (epic-21-implementation.md §3.5, §5 Slice 4). Displays
/// `RenderedD2Diagram.svg` directly via `NSImage(data:)` — unlike
/// Mermaid, no raster snapshot is needed: a real Slice 0 spike confirmed
/// D2's native SVG output (no `<foreignObject>`) displays correctly and
/// crisply via AppKit's own SVG decoder, so this is genuine,
/// resolution-independent vector display on screen, not merely a fixed
/// raster image.
struct D2DiagramBlockView: View {
    let source: String
    let context: D2RenderContext
    let renderer: any D2DiagramRendering

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
                    .accessibilityIdentifier("d2DiagramLoading")
            case let .rendered(image, width, height, svg):
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(width, 640), maxHeight: height)
                    .accessibilityLabel(Text(verbatim: source))
                    .accessibilityIdentifier("d2DiagramImage")
                    .contextMenu {
                        Button("Copy as SVG") {
                            DiagramClipboard.copySVG(svg)
                        }
                        .accessibilityIdentifier("d2DiagramCopyAsSVG")
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
                .accessibilityIdentifier("d2DiagramError")
                .help(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: [source, context.fingerprint]) {
            await render()
        }
    }

    private func render() async {
        let fence = D2Fence(source: source, sourceRange: 0 ..< 0)
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
        guard let renderError = error as? D2RenderError else {
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
