import AppKit
import AppSettings
import OutlineUI
import Preview
import SwiftUI
import Themes

extension DocumentEditorSplitView {
    @ViewBuilder
    var previewPane: some View {
        switch PreviewRouter.previewKind(for: document.format) {
        case .markdown:
            TextualMarkdownPreview(
                document: parseSession.document,
                text: parseSession.publishedText,
                theme: PreviewTheme(theme: themeController.current),
                linkResolver: PreviewLinkResolver(baseURL: document.fileURL),
                controller: scrollController,
                blocks: previewDisplayCache.output,
                mermaidFenceView: mermaidFenceView,
                d2FenceView: d2FenceView,
                graphvizFenceView: graphvizFenceView,
                mathContent: currentMathDisplay?.content ?? .pending,
                onMathSourceAction: { frameID, sourceID in
                    showMathSource(frameID: frameID, sourceID: sourceID, diagnostic: false)
                }
            )
            .environment(\.previewOpenDocument) { [weak coordinator] url in
                Task { @MainActor in await coordinator?.openDocument(at: url) }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    PreviewContributionDiagnosticsBadge(
                        diagnostics: previewContributionSession.displayedDiagnostics(
                            currentRevision: parseSession.document?.revision
                        )
                    )
                    MathPreviewNoticesView(display: currentMathDisplay) { frameID, sourceID in
                        showMathSource(frameID: frameID, sourceID: sourceID, diagnostic: true)
                    }
                    PreviewBusyIndicator(isVisible: parseSession.isParsing || mathSession.isBusy)
                }
            }
        case .html:
            HTMLPreviewPane(model: model, tab: tab, document: document, text: text)
        case .jsonOutline:
            // The JSON preview mode IS the outline: the same format-neutral
            // tree the sidebar shows, with collapse/selection/jump state
            // shared through `outlineController`. The leaf-level identifiers
            // (`jsonOutlinePreviewPane`, `jsonInvalidState`) live inside
            // `JSONOutlinePreviewView`.
            JSONOutlinePreviewView(outlineController: outlineController)
                .overlay(alignment: .topTrailing) { PreviewBusyIndicator(isVisible: jsonSession.isAnalyzing) }
        case .none:
            NoPreviewView(formatName: document.format.name)
        }
    }
}

// MARK: - No preview

private struct NoPreviewView: View {
    let formatName: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("No preview for \(formatName)")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("noPreviewPane")
    }
}
