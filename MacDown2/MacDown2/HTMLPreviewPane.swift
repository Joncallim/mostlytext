import FileCore
import Preview
import SwiftUI
import Workspace

// MARK: - HTML source / rendered preview pane

/// The HTML preview pane: a source ↔ rendered segmented toggle above either
/// the read-only source view or the hardened web-view host.
///
/// The displayed mode is the per-tab choice (`tab.previewMode`) when present,
/// otherwise the format's default. Switching writes the mode back to the tab
/// store and schedules a session save so the choice survives relaunch.
struct HTMLPreviewPane: View {
    let model: WorkspaceModel
    let tab: WorkspaceTab
    let document: FileCore.FileDocument
    let text: String

    @Environment(\.windowCoordinator) private var coordinator

    /// The pane's display mode: the per-tab choice when present, otherwise the
    /// format's default. HTML supports `.source` and `.rendered`.
    private var previewMode: PreviewMode {
        tab.previewMode ?? PreviewRouter.defaultPreviewMode(for: document.format) ?? .rendered
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                switch previewMode {
                case .source:
                    HTMLSourceView(source: text)
                        .accessibilityIdentifier("htmlSourcePane")
                case .rendered, .outline:
                    SecuredHTMLPreviewView(document: document, tabID: tab.id)
                        .accessibilityIdentifier("htmlRenderedPane")
                }
                modePicker
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(10)
            }
            if previewMode != .source {
                PreviewResourcesNotice(model: model, document: document)
            }
        }
    }

    private var modePicker: some View {
        Picker("Preview Mode", selection: modeBinding) {
            ForEach(document.format.supportedPreviewModes, id: \.self) { mode in
                Text(verbatim: modeLabel(mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("htmlPreviewModeToggle")
    }

    private var modeBinding: Binding<PreviewMode> {
        Binding(
            get: { previewMode },
            set: { newMode in
                model.tabStore.setPreviewMode(newMode, for: tab.id)
                coordinator?.scheduleSaveSession()
            }
        )
    }

    private func modeLabel(_ mode: PreviewMode) -> String {
        switch mode {
        case .source: String(localized: "Source")
        case .rendered: String(localized: "Rendered")
        case .outline: String(localized: "Outline")
        }
    }
}

// MARK: - Source view

/// Read-only source view for the HTML preview's `.source` mode: the raw
/// document text, monospaced, never editable.
private struct HTMLSourceView: NSViewRepresentable {
    let source: String

    func makeNSView(context _: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = source

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context _: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != source
        else { return }
        textView.string = source
    }
}
