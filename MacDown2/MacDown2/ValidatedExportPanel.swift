import AppKit
import ExportService
import Foundation
import SwiftUI

/// A disabled, document-window-scoped export sheet. The validated route owns
/// only embedded CSS, so it does not offer the ordinary export's linked-CSS
/// choice until those separate bytes have an ownership receipt.
@MainActor
enum ValidatedExportPanel {
    static func chooseTarget(
        in window: NSWindow, defaultName: String, directory: URL?,
        afterPresentation: (@MainActor (NSSavePanel) -> Void)? = nil
    ) async -> ExportTarget? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export")
        panel.message = String(localized: "Choose where to export this document.")
        panel.directoryURL = directory
        let selection = ExportSelectionModel(format: .standaloneHTML, style: .embedded)
        ExportCoordinator.apply(selection.format, to: panel, defaultBaseName: defaultName)
        let view = ExportPanelView(model: selection, allowsLinkedStyle: false) { [weak panel] format in
            guard let panel else { return }
            ExportCoordinator.apply(format, to: panel, defaultBaseName: defaultName)
        }
        let accessory = NSHostingView(rootView: view)
        accessory.frame = NSRect(origin: .zero, size: accessory.fittingSize)
        panel.accessoryView = accessory

        let session = PanelSession(panel: panel)
        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak session] _ in
            MainActor.assumeIsolated { session?.cancel() }
        }
        defer { NotificationCenter.default.removeObserver(closeObserver) }

        let url = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                guard session.install(continuation) else { return }
                panel.beginSheetModal(for: window) { [weak session] response in
                    session?.finish(response == .OK ? session?.panel.url : nil)
                }
                afterPresentation?(panel)
            }
        } onCancel: {
            session.requestCancel()
        }
        guard let url, !Task.isCancelled else { return nil }
        switch selection.format {
        case .standaloneHTML:
            return .html(url: url, mode: .standalone(style: .embedded))
        case .selfContainedHTML:
            return .html(url: url, mode: .selfContained)
        case .pdf:
            return .pdf(url: url)
        }
    }
}

@MainActor
private final class PanelReply {
    private var continuation: CheckedContinuation<URL?, Never>?
    private var finished = false

    /// Cancellation can arrive before the continuation is installed.
    func install(_ continuation: CheckedContinuation<URL?, Never>) -> Bool {
        guard !finished else {
            continuation.resume(returning: nil)
            return false
        }
        self.continuation = continuation
        return true
    }

    func finish(_ url: URL?) {
        guard !finished else { return }
        finished = true
        let waiting = continuation
        continuation = nil
        waiting?.resume(returning: url)
    }
}

@MainActor
private final class PanelSession {
    let panel: NSSavePanel
    private let reply = PanelReply()

    init(panel: NSSavePanel) {
        self.panel = panel
    }

    func install(_ continuation: CheckedContinuation<URL?, Never>) -> Bool {
        reply.install(continuation)
    }

    func finish(_ url: URL?) {
        reply.finish(url)
    }

    func cancel() {
        reply.finish(nil)
        panel.cancel(nil)
    }

    nonisolated func requestCancel() {
        Task { @MainActor in self.cancel() }
    }
}
