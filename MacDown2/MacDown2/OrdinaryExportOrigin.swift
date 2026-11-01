import AppKit
import FileCore
import Foundation

/// The document command target is chosen before an asynchronous export panel
/// can change window focus. Only the document value is refreshed after the
/// panel; its original window and logical lifetime cannot be replaced.
@MainActor
final class OrdinaryExportOrigin {
    private weak var controller: WindowController?
    private weak var window: NSWindow?
    private let tabID: UUID
    private let documentID: String
    private let recoveryEpoch: UUID
    let operationID = UUID()
    let initialDocument: FileDocument

    private init(controller: WindowController, window: NSWindow, tabID: UUID, document: FileDocument) {
        self.controller = controller
        self.window = window
        self.tabID = tabID
        documentID = document.id
        recoveryEpoch = document.recoveryEpoch
        initialDocument = document
    }

    static func capture(controller: WindowController) -> OrdinaryExportOrigin? {
        guard !controller.isClosed, let window = controller.window,
              let tabID = controller.model.tabStore.activeTabID,
              let document = controller.model.activeDocument,
              document.format.id == "markdown"
        else { return nil }
        return OrdinaryExportOrigin(controller: controller, window: window, tabID: tabID, document: document)
    }

    var presentableWindow: NSWindow? {
        guard let controller, !controller.isClosed, let window,
              controller.window === window
        else { return nil }
        return window
    }

    func canRevealOutput(isCancelled: Bool) -> Bool {
        !isCancelled && presentableWindow != nil
    }

    func documentAfterPanel() throws -> FileDocument {
        guard let controller, presentableWindow != nil,
              controller.model.tabStore.activeTabID == tabID,
              let document = controller.model.activeDocument,
              document.id == documentID,
              document.recoveryEpoch == recoveryEpoch,
              document.format.id == "markdown"
        else { throw CancellationError() }
        return document
    }
}

/// A sheet close or task cancellation must release its awaiting command once,
/// even if AppKit also delivers the normal panel completion callback.
@MainActor
final class OrdinaryExportPanelSession {
    let panel: NSSavePanel
    private var continuation: CheckedContinuation<URL?, Never>?
    private var finished = false

    init(panel: NSSavePanel) {
        self.panel = panel
    }

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

    func cancel() {
        finish(nil)
        panel.cancel(nil)
    }

    nonisolated func requestCancel() {
        Task { @MainActor in self.cancel() }
    }
}

@MainActor
final class OrdinaryExportAlertSession {
    private let alert: NSAlert
    private weak var window: NSWindow?
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    init(alert: NSAlert, window: NSWindow) {
        self.alert = alert
        self.window = window
    }

    func observeOriginClose() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    func install(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
        guard !finished else {
            continuation.resume()
            return false
        }
        self.continuation = continuation
        return true
    }

    func finish() {
        guard !finished else { return }
        finished = true
        let waiting = continuation
        continuation = nil
        waiting?.resume()
    }

    func cancel() {
        finish()
        if let window, alert.window.sheetParent === window {
            window.endSheet(alert.window)
        }
    }

    nonisolated func requestCancel() {
        Task { @MainActor in self.cancel() }
    }
}
