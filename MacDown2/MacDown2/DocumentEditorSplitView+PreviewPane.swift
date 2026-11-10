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
            VStack(spacing: 0) {
                let parsedFrame = parseSession.document.flatMap {
                    PreviewResourceParsedFrame(parserIdentity: parseSession.identity, document: $0)
                }
                // The renderer may still display cached older blocks while a new parse publishes.
                let frame = previewDisplayCache.output == nil || previewDisplayCache.frame == parsedFrame
                    ? parsedFrame : nil
                SecuredMarkdownResourceHost(
                    tabID: tab.id, document: document, sourceGeneration: document.mutationGeneration,
                    parsedFrame: frame, publishedText: parseSession.publishedText
                ) { loader, loadID in
                    markdownPreview(loader: loader, loadID: loadID)
                }
                PreviewResourcesNotice(model: model, document: document)
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

    private func markdownPreview(loader: PreviewResourceImageLoader, loadID: UUID?) -> some View {
        let headingDisplay = currentHeadingDisplay
        return TextualMarkdownPreview(
            document: parseSession.document,
            text: parseSession.publishedText,
            theme: PreviewTheme(theme: themeController.current),
            linkResolver: PreviewLinkResolver(
                baseURL: document.fileURL,
                headingIndex: headingDisplay?.preparation.index
            ),
            controller: scrollController,
            resourceImageLoader: loader, resourceLoadID: loadID,
            blocks: previewDisplayCache.output,
            mermaidFenceView: mermaidFenceView,
            d2FenceView: d2FenceView,
            graphvizFenceView: graphvizFenceView,
            mathContent: currentMathDisplay?.content ?? .pending,
            onMathSourceAction: { frameID, sourceID in
                showMathSource(frameID: frameID, sourceID: sourceID, diagnostic: false)
            },
            onHeadingAction: { heading, identity in
                guard let bindingID = headingDisplay?.bindingID else { return }
                showHeading(.init(bindingID: bindingID, heading: heading, identity: identity))
            }
        )
        .environment(\.previewOpenDocument) { [weak coordinator] url in
            Task { @MainActor in await coordinator?.openDocument(at: url) }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                PreviewContributionDiagnosticsBadge(
                    diagnostics: previewContributionSession.displayedDiagnostics(
                        currentRevision: parseSession.document?.revision,
                        documentIdentity: parseSession.identity
                    )
                )
                MathPreviewNoticesView(display: currentMathDisplay) { frameID, sourceID in
                    showMathSource(frameID: frameID, sourceID: sourceID, diagnostic: true)
                }
                PreviewBusyIndicator(
                    isVisible: parseSession.isParsing || mathSession.isBusy || headingSession.phase == .analyzing
                )
            }
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
