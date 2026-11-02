import AppKit
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
import JSONSupport
import MarkdownEngine
import OutlineUI
import SwiftUI
import TextSearch
import Themes
import Workspace

/// A single document window. Each window is also a tab when grouped by the
/// native tab bar.
@MainActor
final class WindowController: NSWindowController, NSWindowDelegate {
    let model: WorkspaceModel
    let editorStore: EditorTextSystemStore
    /// Current-document Find bar state, one per tab identity (EPIC-22
    /// §6.14, Slice 5a) — mirrors `editorStore`'s own per-window lifecycle.
    let findStore: EditorFindModelStore
    let highlightStore: SyntaxHighlightStore
    let parseStore: MarkdownParseStore
    let jsonAnalysisStore: JSONAnalysisStore
    let themeController: ThemeController
    let outlineController: OutlineController
    let fileTreeModel: FileTreeModel
    /// One index per window, mirroring `fileTreeModel`'s own per-window
    /// scope (EPIC-22 §6.15, Slice 6a) — kept in sync with
    /// `fileTreeModel.root` exclusively through `setFolderRoot(_:accessURL:)`
    /// below, never mutated directly by any other call site.
    let workspaceFileIndex: WorkspaceFileIndex
    /// Window-local preview authority. Every renderer load receives its own revocable token.
    let previewResourceState = PreviewResourceWindowState()
    /// Weak registrations for the disabled validated export path. The origin
    /// retains the lease; the window only needs to revoke it at identity loss.
    var validatedExportLeases: [WeakValidatedExportLease] = []
    /// Test seam: runs just before a root switch awaits the new root's tree and index rebuild.
    var beforeRootRebuild: (@MainActor () async -> Void)?
    /// Folder-wide search sidebar state (EPIC-22 §6.16, Slice 7b), one per
    /// window mirroring `workspaceFileIndex`'s own scope and kept in sync
    /// with `fileTreeModel.root` through the same
    /// `setFileTreeRoot(_:accessURL:)` call site (`WindowController+WorkspaceIndex.swift`).
    let folderSearchModel: FolderSearchModel
    let externalFileController: ExternalFileController
    weak var coordinator: WindowCoordinator?
    let commandDocumentLifetime = UUID()
    private(set) var isClosed = false
    private var observationTask: Task<Void, Never>?
    /// Running text-filter commands, keyed by tab — see
    /// `WindowController+TextFilterTasks.swift`.
    var textFilterTaskHandles: [UUID: TextFilterTaskHandle] = [:]
    private var lastObservedTitle: String = ""
    private var lastObservedDirty: Bool = false
    private var lastObservedURL: URL?
    private var lastObservedLanguageID: String?
    /// When the workspace index was last re-walked (`refreshWorkspaceIndex`).
    var lastWorkspaceIndexRefresh: Date?
    var lastWorkspaceIndexRefreshRoot: URL?
    /// Root-request identity prevents an older A → B → A completion from
    /// claiming freshness for the latest request that happens to use the same URL.
    var workspaceRootRequestGeneration: UInt = 0
    /// A refresh may use the current tree root only after the current explicit
    /// root request has applied it. After that point, accepted renames may
    /// remap the actual root without starting a new request.
    var workspaceTreeRootAppliedGeneration: UInt?
    /// Identifies which overlapping index rebuild may publish completion.
    var workspaceIndexBuildGeneration: UInt = 0
    var lastWorkspaceIndexRefreshGeneration: UInt?
    var pendingFolderSearchRoot: URL?
    var pendingFolderSearchRootGeneration: UInt?

    init(
        model: WorkspaceModel,
        coordinator: WindowCoordinator,
        themeController: ThemeController,
        grammarRegistry: GrammarRegistry,
        fileTreePreferences: FileTreePreferences,
        recoveryExecutor: any RecoveryActionExecuting = DefaultRecoveryActionExecutor(),
        workspaceFileIndex: WorkspaceFileIndex = WorkspaceFileIndex()
    ) {
        self.model = model
        self.coordinator = coordinator
        self.themeController = themeController
        editorStore = EditorTextSystemStore()
        findStore = EditorFindModelStore()
        highlightStore = SyntaxHighlightStore(registry: grammarRegistry)
        // 100 ms debounce + ≤50 ms parse/slice/render pipeline = the 150 ms
        // keystroke-to-preview budget (plan D8). The package default stays at
        // 150 ms so other consumers of `MarkdownParseStore` keep the
        // conservative, E06-tested value; this is the one call site that
        // opts into the tighter production budget.
        parseStore = MarkdownParseStore(debounce: .milliseconds(100))
        jsonAnalysisStore = JSONAnalysisStore(debounce: .milliseconds(100))
        outlineController = OutlineController()
        fileTreeModel = Self.makeFileTreeModel(preferences: fileTreePreferences)
        self.workspaceFileIndex = workspaceFileIndex
        folderSearchModel = FolderSearchModel(index: workspaceFileIndex)
        externalFileController = Self.makeExternalFileController(
            model: model,
            editorStore: editorStore,
            coordinator: coordinator,
            recoveryExecutor: recoveryExecutor
        )

        // Eagerly create the text system and parse session for the active tab
        // so session-save can read cursor/scroll state and the preview can
        // render immediately once SwiftUI mounts the view.
        let shell = WorkspaceShellView(
            model: model,
            editorStore: editorStore,
            findStore: findStore,
            highlightStore: highlightStore,
            parseStore: parseStore,
            jsonAnalysisStore: jsonAnalysisStore,
            themeController: themeController,
            outlineController: outlineController,
            fileTreeModel: fileTreeModel,
            folderSearchModel: folderSearchModel,
            externalFileController: externalFileController
        )
        .environment(\.windowCoordinator, coordinator)
        .environment(\.previewResourceWindowState, previewResourceState)
        let hostingController = NSHostingController(rootView: shell)
        let window = DocumentWindow(contentViewController: hostingController)
        window.coordinator = coordinator
        Self.restoreFrame(of: window)
        window.title = model.activeDocument?.fileURL?.lastPathComponent ?? "Untitled"
        window.minSize = NSSize(width: 400, height: 300)
        window.tabbingMode = .preferred

        super.init(window: window)
        installPreviewIdentityInvalidation()
        makeSessionsForActiveTab()
        externalFileController.attach(owner: self)
        installFolderSearchHooks()
        installSaveAsGuard()
        window.delegate = self
        startWindowObservations()
    }

    private func startWindowObservations() {
        fileTreeModel.startObservingPreferences()
        updateTitleAndEditedState()
        startObservingActiveDocument()
        externalFileController.start()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// Eagerly creates the text system and both analysis sessions for the
    /// active tab so session-save can read cursor/scroll state and the preview
    /// can render immediately once SwiftUI mounts the view.
    ///
    /// Only a system created HERE is marked as awaiting its `EditorView`. SwiftUI can mount the editor
    /// synchronously while `init` builds and frames the hosting window, before this runs; that mount's
    /// `makeNSView` has then already created the system and cleared the flag, and re-marking it would refuse
    /// every command edit (Bold, Text Filter, snippets, Convert Line Endings) for as long as that mount lives —
    /// found by the first real run of `EditingAssistsUITests` (mount logged before `setAwaitingEditorView`).
    private func makeSessionsForActiveTab() {
        guard let activeTab = model.tabStore.activeTab else { return }
        let identity = activeTab.id.uuidString
        let alreadyCreatedByAMountedEditor = editorStore.existingSystem(for: identity) != nil
        let system = editorStore.system(
            for: identity,
            initialText: activeTab.document.text,
            configuration: .default
        )
        if !alreadyCreatedByAMountedEditor {
            system.setAwaitingEditorView(true)
        }
        _ = parseStore.session(for: identity)
        _ = jsonAnalysisStore.session(for: identity)
    }

    private static func makeExternalFileController(
        model: WorkspaceModel,
        editorStore: EditorTextSystemStore,
        coordinator: WindowCoordinator,
        recoveryExecutor: any RecoveryActionExecuting
    ) -> ExternalFileController {
        ExternalFileController(
            model: model,
            editorStore: editorStore,
            identity: model.tabStore.activeTab?.id.uuidString ?? UUID().uuidString,
            coordinator: coordinator,
            monitor: AppDelegate.uiTestingFileMonitorDebounce.map { DocumentFileMonitor(debounce: $0) }
                ?? DocumentFileMonitor(),
            recoveryExecutor: recoveryExecutor
        )
    }

    private static func makeFileTreeModel(preferences: FileTreePreferences) -> FileTreeModel {
        FileTreeModel(
            preferences: preferences,
            supportedExtensions: Set(FileFormatRegistry.defaultFormats.flatMap(\.extensions))
        )
    }

    deinit {
        observationTask?.cancel()
        let controller = externalFileController
        Task { @MainActor in
            controller.dispose()
        }
    }

    private func startObservingActiveDocument() {
        // Polling is used instead of `withObservationTracking` because the
        // observation closure in the previous implementation leaked the task.
        // Keep the active native tab responsive, but do not wake every hidden
        // tab four times a second solely to re-check its title.
        observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                updateTitleAndEditedState()
                let interval: Duration = window?.isKeyWindow == true ? .milliseconds(250) : .seconds(1)
                try? await Task.sleep(for: interval)
            }
        }
    }

    func updateTitleAndEditedState() {
        let document = model.activeDocument
        previewResourceState.reconcile(with: document)
        let baseTitle = document?.fileURL?.lastPathComponent ?? "Untitled"
        let isDirty = document?.state == .dirty || document?.state == .conflict
        let title = isDirty ? "● \(baseTitle)" : baseTitle
        let url = document?.fileURL

        let changed = title != lastObservedTitle || isDirty != lastObservedDirty || url != lastObservedURL
        lastObservedTitle = title
        lastObservedDirty = isDirty
        lastObservedURL = url
        if changed {
            window?.title = title
            window?.representedURL = url
            window?.isDocumentEdited = isDirty
            coordinator?.scheduleSaveSession()
        }

        // Re-attach the highlighter if the active document's format changed
        // (e.g., after Save As). The `highlighter(for:)` method on
        // `SyntaxHighlightStore` detects the language mismatch and calls
        // `setLanguage` automatically.
        let currentLanguageID = model.tabStore.activeTab?.syntaxFormat.highlightLanguageID
        if lastObservedLanguageID != currentLanguageID {
            lastObservedLanguageID = currentLanguageID
            guard let activeTab = model.tabStore.activeTab,
                  let textSystem = editorStore.existingSystem(for: activeTab.id.uuidString)
            else {
                return
            }
            _ = highlightStore.highlighter(
                for: activeTab.id.uuidString,
                textSystem: textSystem,
                languageID: currentLanguageID,
                theme: themeController.current
            )
        }
    }

    func windowWillClose(_: Notification) {
        isClosed = true
        coordinator?.commandReceiver?.documentClosed(commandDocumentLifetime)
        revokeValidatedExports()
        previewResourceState.close()
        previewResourceState.setCurrentPreviewDocument(nil)
        model.tabStore.setActiveIdentityWillChange(nil)
        model.setFolderAssociationWillChange(nil)
        fileTreeModel.setRootAccessWillChange(nil)
        workspaceRootRequestGeneration &+= 1
        workspaceTreeRootAppliedGeneration = nil
        workspaceIndexBuildGeneration &+= 1
        lastWorkspaceIndexRefresh = nil
        lastWorkspaceIndexRefreshRoot = nil
        lastWorkspaceIndexRefreshGeneration = nil
        pendingFolderSearchRoot = nil
        pendingFolderSearchRootGeneration = nil
        observationTask?.cancel()
        externalFileController.dispose()
        editorStore.evictAll()
        findStore.evictAll()
        highlightStore.evictAll()
        parseStore.evictAll()
        jsonAnalysisStore.evictAll()
        fileTreeModel.dispose()
        cancelAllTextFilterTasks()
    }

    /// Explicit-target Save never calls a model method that is permitted to
    /// present an ambient destination panel. `saveWithoutDestinationPrompt()`
    /// performs the backing check inside the same Save attempt (including its
    /// metadata-conflict retry) and either handles the save or reports that a
    /// destination is required. Only the latter path invokes this controller's
    /// window-bound Save As flow. This closes the fourth-pass TOCTOU left by
    /// checking `requiresDestinationToSave` and then calling ordinary `save()`.
    func saveDocumentFromExplicitOrigin() async {
        switch await model.saveWithoutDestinationPrompt() {
        case .handled:
            externalFileController.synchronize(with: model.activeDocument)
            updateTitleAndEditedState()
        case .requiresDestination:
            await saveDocumentAsFromExplicitOrigin()
        }
    }

    /// The coordinator may reserve at synchronous command dispatch; other
    /// callers reserve here before recovery draining or panel presentation.
    /// Both paths bind the destination picker to this window.
    func saveDocumentAsFromExplicitOrigin(
        expecting reservedDocument: FileCore.FileDocument? = nil,
        admission reservedAdmission: WorkspaceModel.SaveAsAdmission? = nil
    ) async {
        defer {
            externalFileController.synchronize(with: model.activeDocument)
            updateTitleAndEditedState()
        }
        guard let document = reservedDocument ?? model.activeDocument else { return }
        guard let admission = reservedAdmission ?? model.reserveSaveAs(for: document) else { return }
        defer { model.finishSaveAs(admission) }
        await externalFileController.drainRecovery()
        guard model.isAdmittedSaveAsCurrent(admission, for: document) else { return }
        let provider = NSFilePanelProvider(window: window)
        guard let url = await provider.chooseSaveLocation(
            defaultName: WorkspaceModel.defaultSaveAsName(for: document),
            format: document.format
        ) else { return }
        // `expecting: document` — the one this Save As was started for,
        // captured above before the panel. The panel stays open as long as
        // the user takes to answer it, and an external-change reload or a
        // tab activation can replace this window's active document while
        // it is up (a sheet blocks neither); without this the save would
        // write whichever document is active *now* to the name the user
        // chose for that one.
        await model.saveAs(to: url, expecting: document, admission: admission)
    }
}

extension WindowController {
    func saveDocumentAs() async {
        await saveDocumentAsFromExplicitOrigin()
    }
}

private extension WindowController {
    func installPreviewIdentityInvalidation() {
        previewResourceState.setCurrentPreviewDocument { [weak model] in
            (model?.tabStore.activeTabID, model?.activeDocument)
        }
        let invalidate: @MainActor () -> Void = { [weak self, weak state = previewResourceState] in
            self?.revokeValidatedExports()
            state?.invalidateForIdentityChange()
        }
        model.tabStore.setActiveIdentityWillChange { _, _ in invalidate() }
        model.setFolderAssociationWillChange(invalidate)
        fileTreeModel.setRootAccessWillChange { [weak self] in
            invalidate()
            // A vanished or replaced folder scope must retire the old
            // search rows synchronously, before a watcher or root rebuild
            // can leave them actionable against a different folder.
            self?.folderSearchModel.rootAccessWasRevoked()
        }
    }
}

extension WindowController {
    func windowDidBecomeKey(_: Notification) {
        // Called by AppKit when this window (or tab) becomes key. This is the
        // deterministic hook for native tab switches, and it only fires for
        // document windows because the coordinator is their delegate.
        coordinator?.updateKeyModel()
        coordinator?.scheduleSaveSession()
        // The inactive polling cadence is intentionally low; refresh once
        // synchronously when a native tab becomes visible again.
        updateTitleAndEditedState()
        externalFileController.retryMonitoring()
        Task {
            await fileTreeModel.rescanExpandedDirectories()
            await refreshWorkspaceIndex(minInterval: 5)
        }
    }
}
