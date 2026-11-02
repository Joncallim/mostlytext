import AppKit
import Darwin
import FileCore
import Foundation
import os
import Workspace

/// Evidence of an explicit folder-panel choice for one document. This value is not a resource grant:
/// the caller must still acquire a retained directory backing and reject a stale document/window epoch.
struct PreviewResourceFolderSelection {
    let requestedDocumentURL: URL
    let selectedFolderURL: URL
    let selectedDevice: Int64
    let selectedInode: UInt64

    private init(requestedDocumentURL: URL, selectedFolderURL: URL, selectedInfo: stat) {
        self.requestedDocumentURL = requestedDocumentURL
        self.selectedFolderURL = selectedFolderURL
        selectedDevice = Int64(selectedInfo.st_dev)
        selectedInode = UInt64(selectedInfo.st_ino)
    }

    fileprivate static func capture(documentURL: URL, folderURL: URL) -> Self? {
        var selectedInfo = stat()
        guard fstatat(AT_FDCWD, folderURL.path, &selectedInfo, 0) == 0,
              (selectedInfo.st_mode & S_IFMT) == S_IFDIR
        else { return nil }
        return Self(requestedDocumentURL: documentURL, selectedFolderURL: folderURL, selectedInfo: selectedInfo)
    }

    #if DEBUG || RELEASE_PREVIEW_PROBE
        /// Focused grant tests and the opt-in Release probe exercise capture/open without a native sheet.
        /// The probe condition is never set for the distributable app.
        static func fixture(documentURL: URL, folderURL: URL) -> Self? {
            capture(documentURL: documentURL, folderURL: folderURL)
        }
    #endif
}

/// AppKit implementation of `FilePanelProviding` for the MacDown 2 app target.
///
/// Application commands may use the key window or a modal panel. A command
/// captured from a document window may use only that window.
@MainActor
final class NSFilePanelProvider: FilePanelProviding {
    @MainActor
    private final class WeakOrigin {
        weak var window: NSWindow?
        let hadWindowAtInvocation: Bool
        private var closed = false
        private var closeObserver: NSObjectProtocol?

        init(_ window: NSWindow?) {
            self.window = window
            hadWindowAtInvocation = window != nil
            if let window {
                closeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: window, queue: nil
                ) { [weak self] _ in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { self?.closed = true }
                    } else {
                        Task { @MainActor in self?.closed = true }
                    }
                }
            }
        }

        isolated deinit {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
        }

        var usableWindow: NSWindow? {
            closed ? nil : window
        }
    }

    private enum Origin {
        case applicationInitiated
        case capturedApplication(WeakOrigin)
        case explicit(WeakOrigin)
    }

    enum Presentation {
        case sheet(NSWindow)
        case modal
        case cancelled
    }

    private let origin: Origin

    init() {
        origin = .applicationInitiated
    }

    init(window: NSWindow?) {
        origin = .explicit(WeakOrigin(window))
    }

    /// Captures a normal Open command's application window at dispatch. A
    /// later key-window change cannot silently retarget the panel or document.
    init(applicationWindow: NSWindow?) {
        origin = .capturedApplication(WeakOrigin(applicationWindow))
    }

    var scopedOpenWindow: NSWindow? {
        switch origin {
        case .applicationInitiated:
            nil
        case let .capturedApplication(origin), let .explicit(origin):
            origin.usableWindow
        }
    }

    var canCompleteScopedOpen: Bool {
        switch origin {
        case .applicationInitiated:
            true
        case let .capturedApplication(origin):
            !origin.hadWindowAtInvocation || origin.usableWindow != nil
        case let .explicit(origin):
            origin.usableWindow != nil
        }
    }

    func presentation(keyWindow: NSWindow?) -> Presentation {
        switch origin {
        case .applicationInitiated:
            if let keyWindow {
                return .sheet(keyWindow)
            }
            return .modal
        case let .capturedApplication(origin):
            if !origin.hadWindowAtInvocation {
                return .modal
            }
            guard let window = origin.usableWindow else {
                return .cancelled
            }
            return .sheet(window)
        case let .explicit(origin):
            guard let window = origin.usableWindow else {
                return .cancelled
            }
            return .sheet(window)
        }
    }

    func chooseFile() async -> URL? {
        await chooseFile(trace: nil)
    }

    /// The normal Open command supplies one trace from command receipt through
    /// the panel becoming key. Other file pickers keep the same panel behavior.
    func chooseFile(trace: OpenPanelTrace?) async -> URL? {
        trace?.markConstructionStart()
        let panel = NSOpenPanel()
        trace?.markConstructed()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = FileFormatRegistry.defaultFormats.map(\.utType)
        trace?.markConfigured()

        let readiness = PanelReadinessObserver(panel: panel, trace: trace)
        let selected = await present(panel, trace: trace)
        readiness.finish()
        return selected
    }

    func chooseFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Folder"

        return await present(panel)
    }

    /// Obtains a folder from a dedicated document-relative panel. The result only records user selection;
    /// no preview resource is admitted until the #121 grant owner pins and verifies the chosen directory.
    func choosePreviewResourceFolder(near documentURL: URL) async -> PreviewResourceFolderSelection? {
        // A document-specific permission prompt cannot migrate to a different key window while awaiting the panel.
        guard documentURL.isFileURL,
              case let .sheet(window) = presentation(keyWindow: nil)
        else { return nil }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = documentURL.deletingLastPathComponent()

        let selectedFolderURL = await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { result in
                continuation.resume(returning: result == .OK ? panel.urls.first : nil)
            }
        }
        guard let selectedFolderURL else { return nil }
        // Capture object identity at the selection edge. A later path replacement cannot become the grant merely
        // because it has the same spelling; the backing compares its opened descriptor to this identity.
        return PreviewResourceFolderSelection.capture(documentURL: documentURL, folderURL: selectedFolderURL)
    }

    func chooseSaveLocation(defaultName: String, format: FileFormat) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true

        return await present(panel)
    }

    private func present(_ panel: NSOpenPanel, trace: OpenPanelTrace? = nil) async -> URL? {
        await withCheckedContinuation { continuation in
            switch presentation(keyWindow: NSApp.keyWindow) {
            case let .sheet(targetWindow):
                let request = PanelRequest(continuation, window: targetWindow)
                trace?.markPresentation()
                panel.beginSheetModal(for: targetWindow) { result in
                    request.finish(result == .OK ? panel.urls.first : nil)
                }
            case .modal:
                trace?.markPresentation()
                let result = panel.runModal()
                continuation.resume(returning: result == .OK ? panel.urls.first : nil)
            case .cancelled:
                continuation.resume(returning: nil)
            }
        }
    }

    private func present(_ panel: NSSavePanel) async -> URL? {
        await withCheckedContinuation { continuation in
            switch presentation(keyWindow: NSApp.keyWindow) {
            case let .sheet(targetWindow):
                let request = PanelRequest(continuation, window: targetWindow)
                panel.beginSheetModal(for: targetWindow) { result in
                    request.finish(result == .OK ? panel.url : nil)
                }
            case .modal:
                let result = panel.runModal()
                continuation.resume(returning: result == .OK ? panel.url : nil)
            case .cancelled:
                continuation.resume(returning: nil)
            }
        }
    }
}

/// Instrumentation for a normal Open command. A key-window notification is
/// first observable readiness, not proof that a rendered frame was painted.
@MainActor
final class OpenPanelTrace {
    private static let signposter = OSSignposter(subsystem: "com.joncallim.MacDown2", category: "OpenPanel")
    private static let logger = Logger(subsystem: "com.joncallim.MacDown2", category: "OpenPanel")
    private let id = signposter.makeSignpostID()
    private let received = ContinuousClock.now
    private var constructionStarted: ContinuousClock.Instant?
    private var wasReady = false

    init() {
        Self.signposter.emitEvent("CommandReceived", id: id)
    }

    func markConstructionStart() {
        constructionStarted = .now
        Self.signposter.emitEvent("ConstructionStarted", id: id)
        let milliseconds = elapsedMilliseconds(since: received)
        Self.logger.info("Open command to construction: \(milliseconds) ms")
    }

    func markConstructed() {
        Self.signposter.emitEvent("Constructed", id: id)
        if let constructionStarted {
            let milliseconds = elapsedMilliseconds(since: constructionStarted)
            Self.logger.info("Open panel construction: \(milliseconds) ms")
        }
    }

    func markConfigured() {
        Self.signposter.emitEvent("Configured", id: id)
        let milliseconds = elapsedMilliseconds(since: received)
        Self.logger.info("Open command to configuration: \(milliseconds) ms")
    }

    func markPresentation() {
        Self.signposter.emitEvent("PresentationStarted", id: id)
        let milliseconds = elapsedMilliseconds(since: received)
        Self.logger.info("Open command to presentation: \(milliseconds) ms")
    }

    func markReady() {
        guard !wasReady else { return }
        wasReady = true
        Self.signposter.emitEvent("BecameKey", id: id)
        let milliseconds = elapsedMilliseconds(since: received)
        Self.logger.info("Open command to panel key: \(milliseconds) ms")
    }

    func markFinished() {
        if !wasReady {
            Self.logger.info("Open panel ended without an observed key-window event")
        }
    }

    private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Int64 {
        let components = start.duration(to: .now).components
        return components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    }
}

@MainActor
private final class PanelReadinessObserver {
    private var observer: NSObjectProtocol?
    private let trace: OpenPanelTrace?

    init(panel: NSOpenPanel, trace: OpenPanelTrace?) {
        self.trace = trace
        guard trace != nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: panel, queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.trace?.markReady() }
            } else {
                Task { @MainActor in self?.trace?.markReady() }
            }
        }
    }

    func finish() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        trace?.markFinished()
    }
}

@MainActor
private final class PanelRequest {
    private var continuation: CheckedContinuation<URL?, Never>?
    private var closeObserver: NSObjectProtocol?

    init(_ continuation: CheckedContinuation<URL?, Never>, window: NSWindow) {
        self.continuation = continuation
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: nil
        ) { [self] _ in
            Task { @MainActor in finish(nil) }
        }
    }

    func finish(_ url: URL?) {
        guard let continuation else { return }
        self.continuation = nil
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        continuation.resume(returning: url)
    }
}
