import AppKit
import SwiftUI

struct LicenseNoticesView: View {
    private enum Document: Hashable { case product, thirdParty }

    @State private var selected: Document = .product
    @State private var findRequest = 0
    private let content: LicenseNoticesContent?

    init() {
        content = try? LicenseNoticesContent.load()
    }

    var body: some View {
        VStack(spacing: 12) {
            if let content {
                Picker("License document", selection: $selected) {
                    Text("MostlyText license").tag(Document.product)
                    Text("Third-party notices").tag(Document.thirdParty)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("licenses.documentPicker")

                LicenseTextView(
                    text: selected == .product ? content.productLicense : content.thirdPartyNotices,
                    label: selected == .product
                        ? String(localized: "MostlyText license") : String(localized: "Third-party notices"),
                    findRequest: findRequest
                )
            } else {
                Text("License texts could not be loaded from this application.")
                    .accessibilityIdentifier("licenses.loadFailure")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
        .focusedSceneValue(\.licenseFindAction, content.map { _ in
            LicenseFindAction(perform: { findRequest += 1 })
        })
    }
}

/// Plain native text preserves the shipped wording and never makes a notice's
/// URL or markup active. Find and Copy remain standard AppKit operations.
struct LicenseTextView: NSViewRepresentable {
    let text: String
    let label: String
    var findRequest = 0

    final class Coordinator {
        var lastFindRequest = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> NSScrollView {
        Self.makeScrollView(text: text, label: label)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let view = scrollView.documentView as? NSTextView else { return }
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
        view.setAccessibilityLabel(label)
        if context.coordinator.lastFindRequest != findRequest {
            context.coordinator.lastFindRequest = findRequest
            Self.showFind(in: view)
        }
    }

    static func makeScrollView(text: String, label: String) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        let view = NSTextView(frame: scroll.contentView.bounds)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.allowsUndo = false
        view.usesFindPanel = true
        view.isAutomaticLinkDetectionEnabled = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude
        )
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        view.string = text
        view.setAccessibilityLabel(label)
        view.setAccessibilityIdentifier("licenses.content")
        scroll.documentView = view
        return scroll
    }

    static func showFind(in view: NSTextView) {
        view.window?.makeFirstResponder(view)
        let sender = NSMenuItem()
        sender.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        view.performFindPanelAction(sender)
    }
}
