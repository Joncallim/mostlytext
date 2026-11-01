import AppKit
import AppSettings
import Contributions
import ExportService
import FileCore
import Foundation
import MarkdownEngine
import SwiftUI
import Themes
import UniformTypeIdentifiers
import Workspace

/// Orchestrates export for the active document: reads the live editor snapshot,
/// presents the export panel (save location + options), composes the export
/// off the main actor, and surfaces the result or the error.
///
/// It is a value type with no stored state of its own: the window coordinator
/// hands one out per menu evaluation, and nothing must survive between them.
@MainActor
struct ExportCoordinator {
    private let coordinator: WindowCoordinator
    private let themeController: ThemeController
    private let appSettings: AppSettingsModel

    init(coordinator: WindowCoordinator, themeController: ThemeController, appSettings: AppSettingsModel) {
        self.coordinator = coordinator
        self.themeController = themeController
        self.appSettings = appSettings
    }

    /// How many diagnostics one alert lists before it summarises the rest.
    private let diagnosticsShownAtMost = 6

    /// Whether the selected document is exportable Markdown and
    /// does not already have an export in flight.
    var canExportActiveDocument: Bool {
        _ = coordinator.commandStateRevision
        guard let model = coordinator.currentCommandController(
            keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow
        )?.model, model.activeDocument?.format.id == "markdown" else {
            return false
        }
        return !coordinator.isExporting(model)
    }

    /// Presents the export panel and performs the requested export.
    ///
    /// Re-entrancy guard: two ⌘⇧E while a save panel or a slow PDF render is
    /// still in flight must not start two exports of the same document
    /// racing the same destination file. Scoped to `model` (one per window),
    /// set for the whole call including panel presentation — cancelling the
    /// panel already exits through the same `defer`.
    @discardableResult
    func beginExportActiveDocument() -> Task<Void, Never>? {
        let controller = coordinator.currentCommandController(
            keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow
        )
        guard let controller, let window = controller.window, window.isVisible,
              let origin = OrdinaryExportOrigin.capture(controller: controller)
        else { return nil }
        let model = controller.model
        guard !coordinator.isExporting(model) else { return nil }

        coordinator.setExporting(true, for: model)
        return Task { @MainActor in
            defer { coordinator.setExporting(false, for: model) }
            await export(from: origin)
        }
    }

    private func export(from origin: OrdinaryExportOrigin) async {
        guard let window = origin.presentableWindow else { return }
        let document = origin.initialDocument

        let baseName = document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        let directory = document.fileURL?.deletingLastPathComponent()

        guard let selection = await presentExportPanel(
            in: window, defaultName: baseName, directory: directory
        ) else {
            return
        }

        do {
            try Task.checkCancellation()
            // A panel can suspend through focus changes, Save As, or document
            // replacement. Read the editor-published value only after its
            // original window and document lifetime are checked again.
            let document = try origin.documentAfterPanel()
            let snapshot = OrdinaryExportSnapshot(
                document: document,
                theme: themeController.current,
                parseOptions: DocumentEditorSplitView.markdownParseOptions(from: appSettings.markdown)
            )
            let result = try await performExport(snapshot: snapshot, selection: selection)
            // Diagnostics are read before Finder takes focus, so the report is
            // not left sitting behind another app's window.
            await presentDiagnosticsIfNeeded(result.diagnostics, from: origin)
            // The diagnostic sheet itself can be cancelled by closing the
            // origin. Also check the empty-diagnostics path, which has no
            // sheet but still resumes after rendering has suspended.
            guard origin.canRevealOutput(isCancelled: Task.isCancelled) else { return }
            reveal(result.primaryFile)
        } catch is CancellationError {
            // The user withdrew the export; there is nothing to report.
        } catch {
            await presentError(error, from: origin)
        }
    }

    // MARK: - Panel

    /// The resolved export choices: the save destination plus the panel's
    /// format and style options.
    struct ExportSelection {
        let url: URL
        let format: ExportFormatOption
        let style: ExportStyleEmbedding
    }

    private func presentExportPanel(
        in window: NSWindow,
        defaultName: String,
        directory: URL?
    ) async -> ExportSelection? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose where to export this document."
        if let directory {
            panel.directoryURL = directory
        }

        let selectionModel = ExportSelectionModel(
            format: Self.exportFormatOption(from: appSettings.previewExport.defaultExportFormat),
            style: Self.exportStyleEmbedding(from: appSettings.previewExport.defaultExportStyle)
        )
        Self.initializeFilename(selectionModel.format, in: panel, defaultBaseName: defaultName)

        let panelView = ExportPanelView(model: selectionModel) { [weak panel] format in
            guard let panel else { return }
            Self.apply(format, to: panel, defaultBaseName: defaultName)
        }
        let accessory = NSHostingView(rootView: panelView)
        // An NSSavePanel accessory is laid out from its frame, so the hosting
        // view is sized before it is attached rather than collapsing to zero.
        accessory.frame = NSRect(origin: .zero, size: accessory.fittingSize)
        panel.accessoryView = accessory

        let session = OrdinaryExportPanelSession(panel: panel)
        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak session] _ in
            MainActor.assumeIsolated { session?.cancel() }
        }
        defer { NotificationCenter.default.removeObserver(closeObserver) }

        let url = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                guard session.install(continuation) else { return }
                panel.beginSheetModal(for: window) { [weak session] result in
                    session?.finish(result == .OK ? session?.panel.url : nil)
                }
            }
        } onCancel: {
            session.requestCancel()
        }

        guard let url, !Task.isCancelled else { return nil }
        return ExportSelection(url: url, format: selectionModel.format, style: selectionModel.style)
    }

    /// Starts with the document's name even when AppKit prepopulates the field.
    /// Later format changes preserve whatever name the user has entered.
    static func initializeFilename(_ format: ExportFormatOption, in panel: NSSavePanel, defaultBaseName: String) {
        panel.nameFieldStringValue = defaultBaseName
        apply(format, to: panel, defaultBaseName: defaultBaseName)
    }

    /// Keeps the panel's filename and enforced content type in step with the
    /// chosen format, so picking PDF cannot save a PDF named `.html`.
    static func apply(_ format: ExportFormatOption, to panel: NSSavePanel, defaultBaseName: String) {
        panel.allowedContentTypes = [format.contentType]

        let typed = panel.nameFieldStringValue
        var base = typed.isEmpty ? defaultBaseName : typed
        // Only an extension this panel could have written is replaced; a name
        // like "Report v1.2" keeps every character the user typed.
        for known in ExportFormatOption.knownExtensions where base.lowercased().hasSuffix(".\(known)") {
            base = String(base.dropLast(known.count + 1))
            break
        }
        if base.isEmpty {
            base = defaultBaseName
        }
        panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
    }

    /// Seeds the panel's initial choice only — the panel itself remains fully
    /// user-editable per export. Does not touch `ExportRequest`/
    /// `ExportComposer`, whose template/layout/resource-root/budget/
    /// metadata-policy are fixed by the composer regardless of preferences
    /// (epic-13-implementation.md §4, invariant 4).
    static func exportFormatOption(
        from preference: PreviewExportSettings.DefaultExportFormat
    ) -> ExportFormatOption {
        switch preference {
        case .standaloneHTML: .standaloneHTML
        case .selfContainedHTML: .selfContainedHTML
        case .pdf: .pdf
        }
    }

    static func exportStyleEmbedding(
        from preference: PreviewExportSettings.DefaultExportStyle
    ) -> ExportStyleEmbedding {
        switch preference {
        case .embedded: .embedded
        case .linked: .linked
        }
    }

    // MARK: - Feedback

    /// Selects the exported document in Finder. Companion files are deliberately
    /// not selected: an image-heavy export would otherwise open Finder with two
    /// dozen items highlighted across two folders.
    private func reveal(_ file: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    /// Composition diagnostics are reported, never dropped: an export that
    /// quietly left images unresolved, or a derived contribution broken, would
    /// look successful and open wrong. This runs only after a successful
    /// export, so an `.error` diagnostic here means one part of the document
    /// did not resolve, not that the export failed — resolution failures that
    /// are fatal to the export itself are thrown from `performExport` and never
    /// reach this point.
    private func presentDiagnosticsIfNeeded(
        _ diagnostics: [ExportDiagnostic], from origin: OrdinaryExportOrigin
    ) async {
        guard !diagnostics.isEmpty else { return }

        let shown = diagnostics.prefix(diagnosticsShownAtMost).map(\.message)
        var text = shown.joined(separator: "\n")
        if diagnostics.count > shown.count {
            text += "\n…and \(diagnostics.count - shown.count) more."
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = diagnostics.count == 1
            ? "Exported with 1 issue"
            : "Exported with \(diagnostics.count) issues"
        alert.informativeText = text
        await present(alert, from: origin)
    }

    private func presentError(_ error: Error, from origin: OrdinaryExportOrigin) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Export Failed")
        alert.informativeText = error.localizedDescription
        if let suggestion = (error as? LocalizedError)?.recoverySuggestion {
            alert.informativeText += "\n\n" + suggestion
        }
        await present(alert, from: origin)
    }

    private func present(_ alert: NSAlert, from origin: OrdinaryExportOrigin) async {
        guard let window = origin.presentableWindow else { return }
        let session = OrdinaryExportAlertSession(alert: alert, window: window)
        let closeObserver = session.observeOriginClose()
        defer { NotificationCenter.default.removeObserver(closeObserver) }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard session.install(continuation) else { return }
                alert.beginSheetModal(for: window) { [weak session] _ in
                    session?.finish()
                }
            }
        } onCancel: {
            session.requestCancel()
        }
    }
}
