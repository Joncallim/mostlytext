import AppKit
import AppSettings
import CommandBridge
import EditorCore
import ExportService
import FileCore
import FileTree
import Foundation
import Highlighting
import Observation
import SwiftUI
import TextFilters
import Themes
import Workspace

extension EnvironmentValues {
    @Entry var windowCoordinator: WindowCoordinator?
    @Entry var themeController: ThemeController?
    @Entry var themeCatalog: ThemeCatalogModel?
    @Entry var appSettings: AppSettingsModel?
}

// MARK: - Coordinator

/// Owns the global document pool and the native `NSWindow` controllers that
/// present each document as a tab.
@MainActor
@Observable
final class WindowCoordinator {
    enum TerminationRecoveryState: Equatable {
        case none
        case recoveryRequired
    }

    /// The model for the document currently shown in the key window.
    private(set) var keyModel: WorkspaceModel?

    /// `controllers`, `sessionStore`, `themeController`, and `grammarRegistry`
    /// are internal rather than private: `WindowCoordinator+SessionRestore.swift`
    /// is a same-module extension in a separate file (split out to stay under
    /// the type-body-length lint budget) and needs them.
    var controllers: [WindowController] = [] {
        willSet { protectExportsBeforePublishing(newValue) }
    }

    @ObservationIgnored let exportDocumentProtections = ExportDocumentProtectionRegistry()
    let sessionStore: WorkspaceSessionStoring
    let panelProvider: NSFilePanelProvider
    let recoveryBuffer: RecoveryBuffer
    let snippetStore: SnippetStore
    let commandsDirectory: URL
    let exportRecoveryLocation: ExportRecoveryLocation?
    let themeController: ThemeController
    let grammarRegistry: GrammarRegistry
    let fileTreePreferences: FileTreePreferences
    let recentFolderRoots: RecentFolderRoots
    let recentFileDocuments: RecentFileDocuments
    let appSettings: AppSettingsModel
    let workspaceStateStore: any WorkspaceStateStoring
    /// Shared by every `WorkspaceModel` this coordinator creates, so a
    /// sidebar-layout edit in one window is immediately reflected in every
    /// other open window rather than only on the next launch (#34).
    let sidebarLayoutBroadcaster = SidebarLayoutBroadcaster()
    private var hasRestoredSession = false
    let documentOpens = KeyedSerialRunner<String>()
    @ObservationIgnored var commandReceiver: CommandApplicationReceiver?
    @ObservationIgnored var commandStdinStages: [WindowController] = [] {
        willSet { protectExportsBeforePublishing(newValue) }
    }

    let commandStdinAdmissions = KeyedSerialRunner<String>()
    var launchSession: WorkspaceSession? // as at launch; handed out once by `consumeLaunchSession()`
    var saveTask: Task<Void, Never>?
    @ObservationIgnored var terminationSaveInProgress = false
    var sessionPublicationOrder = SessionPublicationOrder()
    var afterSessionRecoveryPersisted: (@MainActor () async -> Void)? // test seam: before publishing
    var afterSessionPublicationRejected: (@MainActor (_ superseded: Bool, _ documentChanged: Bool) -> Void)?
    /// Test seam: runs after a new controller's root/index rebuild and before publication.
    var afterFolderSearchRootRebuild: (@MainActor () async -> Void)?
    /// Test seam: runs after file loading and before the post-load continuation check.
    var afterFolderSearchFileLoad: (@MainActor () async -> Void)?
    var afterFolderSearchEditorLayoutChange: (@MainActor () -> Void)?
    var restoreTask: Task<Void, Never>?
    var unsavedRestoreTask: Task<Void, Never>?
    /// Latest-request ownership for folder-search navigation.
    @ObservationIgnored var folderSearchRequestGate = FolderSearchRequestGate()
    @ObservationIgnored var folderSearchNavigationRevision: UInt = 0
    @ObservationIgnored var pendingFolderSearchReveals: [UUID: PendingFolderSearchReveal] = [:]
    // `pendingNewDocumentTasks` and `addController` are internal rather than
    // private for the same reason as the properties above:
    // `WindowCoordinator+NewDocument.swift` is a same-module extension in a
    // separate file and needs them.
    @ObservationIgnored var pendingNewDocumentTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Documents with an export currently in flight. Not `@ObservationIgnored`
    /// — `ExportCoordinator.canExportActiveDocument` reads this on every menu
    /// validation, and the menu item must grey out while its export runs.
    var exportingModels: Set<ObjectIdentifier> = []
    /// Stateless export orchestrator for the active document (E12). A computed
    /// property keeps it outside `@Observable` tracking; the value type means
    /// menu validation, which reads it on every evaluation, allocates nothing.
    var exportCoordinator: ExportCoordinator {
        ExportCoordinator(coordinator: self, themeController: themeController, appSettings: appSettings)
    }

    /// Changes whenever AppKit focus/input can have changed the responder used
    /// by the formatting commands.  SwiftUI commands read this through the
    /// command bridge, so menu validation is invalidated even though AppKit's
    /// first-responder chain is not an Observable value.
    private(set) var commandStateRevision = 0
    @ObservationIgnored var onNewDocumentLifetimePrepared: (@MainActor () async -> Void)?
    @ObservationIgnored var terminationRecoveryState: TerminationRecoveryState = .none
    @ObservationIgnored var terminationRecoveryController: WindowController?
    /// Tests can record a recovery-sheet request without creating native UI.
    /// Nil retains the production alert and its unchanged response handling.
    @ObservationIgnored var terminationRecoveryAlertPresenter: (@MainActor (NSWindow, WindowController?) -> Void)?
    /// The one currently open command-palette panel, if any — see
    /// `WindowCoordinator+CommandPalette.swift` and `CommandPalettePanel`'s
    /// doc comment for why this coordinator must hold it strongly.
    @ObservationIgnored var commandPalette: CommandPalettePanel?
    /// The one currently open Go to Line panel, if any — see
    /// `WindowCoordinator+GoToLine.swift` and `GoToLinePanel`'s doc comment
    /// for why this coordinator must hold it strongly.
    @ObservationIgnored var goToLinePanel: GoToLinePanel?
    /// The one open Quick Open panel / Insert Snippet picker, if any — held
    /// strongly; see `QuickOpenPanel`'s doc comment for why.
    @ObservationIgnored var quickOpen: QuickOpenPanel?
    @ObservationIgnored var snippetPanel: SnippetPickerPanel?
    /// The one currently open first-run welcome window, if any — see
    /// `WindowCoordinator+FirstRun.swift`. Held strongly for the same reason
    /// as `commandPalette`: nothing else references it while it is open.
    @ObservationIgnored var firstRunWindow: FirstRunWindowController?

    init(
        sessionStore: WorkspaceSessionStoring = WorkspaceSessionStore(),
        panelProvider: NSFilePanelProvider = NSFilePanelProvider(),
        recoveryBuffer: RecoveryBuffer = .shared,
        themeController: ThemeController,
        grammarRegistry: GrammarRegistry,
        fileTreePreferences: FileTreePreferences,
        recentFolderRoots: RecentFolderRoots,
        recentFileDocuments: RecentFileDocuments,
        appSettings: AppSettingsModel,
        workspaceStateStore: any WorkspaceStateStoring = WorkspaceStateStore(),
        snippetStore: SnippetStore = SnippetStore(),
        commandsDirectory: URL = TextFilterCommandDiscovery.commandsDirectory,
        exportRecoveryLocation: ExportRecoveryLocation? = nil
    ) {
        self.sessionStore = sessionStore
        self.panelProvider = panelProvider
        self.recoveryBuffer = recoveryBuffer
        self.themeController = themeController
        self.grammarRegistry = grammarRegistry
        self.fileTreePreferences = fileTreePreferences
        self.recentFolderRoots = recentFolderRoots
        self.recentFileDocuments = recentFileDocuments
        self.appSettings = appSettings
        self.workspaceStateStore = workspaceStateStore
        self.snippetStore = snippetStore
        self.commandsDirectory = commandsDirectory
        self.exportRecoveryLocation = exportRecoveryLocation
        launchSession = sessionStore.loadSession()
    }

    // MARK: - Window lifecycle

    /// Shows the open panel and opens the chosen file.
    /// - Parameter relativeTo: when non-`nil`, the panel presents against
    ///   this window explicitly and the opened document opens relative to
    ///   it — used by the command palette (post-review finding #4). The real
    ///   menu path captures the current application window at dispatch.
    func openFile(relativeTo controller: WindowController? = nil) {
        let trace = OpenPanelTrace()
        let provider = controller.map { NSFilePanelProvider(window: $0.window) }
            ?? NSFilePanelProvider(applicationWindow: NSApp.keyWindow)
        Task { @MainActor in
            guard let url = await provider.chooseFile(trace: trace) else { return }
            guard provider.canCompleteScopedOpen else { return }
            await openDocument(
                at: url,
                relativeTo: provider.scopedOpenWindow,
                shouldContinue: { provider.canCompleteScopedOpen },
                useAmbientWindow: false
            )
        }
    }

    /// Selects the next tab in the key window's native tab group.
    func selectNextTab() {
        NSApp.keyWindow?.selectNextTab(nil)
        commandStateDidChange()
    }

    /// Selects the previous tab in the key window's native tab group.
    func selectPreviousTab() {
        NSApp.keyWindow?.selectPreviousTab(nil)
        commandStateDidChange()
    }

    /// Selects a tab by index in the key window's native tab group. Index 8
    /// (⌘9) always means the last tab.
    func selectTab(at index: Int) {
        guard let tabGroup = NSApp.keyWindow?.tabGroup, !tabGroup.windows.isEmpty else { return }
        let targetIndex = (index == 8) ? tabGroup.windows.count - 1 : min(index, tabGroup.windows.count - 1)
        let targetWindow = tabGroup.windows[targetIndex]
        tabGroup.selectedWindow = targetWindow
        // Refresh immediately; the window delegate will also reconcile the key
        // model once AppKit finishes the native-tab transition.
        targetWindow.makeKeyAndOrderFront(nil)
        commandStateDidChange()
    }

    /// `true` if the key window's tab group has more than one tab.
    var keyWindowHasMultipleTabs: Bool {
        guard let count = NSApp.keyWindow?.tabGroup?.windows.count else { return false }
        return count > 1
    }

    /// `true` if the key window's tab group has a tab at the given index.
    func keyWindowHasTab(at index: Int) -> Bool {
        guard let count = NSApp.keyWindow?.tabGroup?.windows.count, count > 0 else { return false }
        if index == 8 {
            return true
        }
        return index < count
    }

    // MARK: - Session

    /// Schedules a session save, debounced so rapid changes coalesce into one
    /// write. Call this after any structural or document change.
    func scheduleSaveSession() {
        sessionPublicationOrder.invalidateCapturedSnapshots()
        saveTask?.cancel()
        guard !terminationSaveInProgress else {
            return
        }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            _ = await saveSessionResult(isAutosave: true)
        }
    }

    /// Begins the launch-time session restore. A short grace period lets a
    /// pending `application(_:openFiles:)` arrive before the restore decision;
    /// `isDocumentOpenPending` is evaluated after that delay. The work is
    /// tracked in `restoreTask` so ``ensureWindowExistsForReopen()`` can await
    /// it instead of racing a new window into existence ahead of the restored
    /// session.
    func scheduleSessionRestore(
        createsUntitledWhenEmpty: Bool = true,
        isDocumentOpenPending: @escaping @MainActor () -> Bool
    ) {
        guard !hasRestoredSession else { return }
        hasRestoredSession = true
        restoreTask = Task { @MainActor [weak self] in
            // Give `application(_:openFiles:)` a few run-loop ticks to arrive
            // before we fall back to restoring the previous session.
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled else { return }
            guard !isDocumentOpenPending() else {
                await restoreUnsavedSessionTabs()
                return
            }
            await restoreSession(createsUntitledWhenEmpty: createsUntitledWhenEmpty)
        }
    }

    /// Awaits any in-flight session restore, then creates an untitled window
    /// if no document window exists. Used by the reopen handler so a reopen
    /// event landing before the restored windows appear does not spawn a
    /// spurious untitled window.
    func ensureWindowExistsForReopen() async {
        await restoreTask?.value
        guard controllers.isEmpty else { return }
        newDocument()
    }

    // MARK: - Internal helpers

    func removeController(_ controller: WindowController) {
        commandReceiver?.documentClosed(controller.commandDocumentLifetime)
        pendingNewDocumentTasks.removeValue(forKey: ObjectIdentifier(controller))?.cancel()
        controllers.removeAll { $0 === controller }
        // The palette must never keep offering (or being able to invoke)
        // commands against a controller that is no longer open — closing
        // it here, rather than merely making it inert, also releases
        // everything the palette retains about it (post-review finding
        // #5). `close()` re-enters via `commandPaletteDidClose`, which
        // clears `commandPalette` itself.
        if commandPalette?.originController === controller {
            commandPalette?.close()
        }
        // Same reasoning as the command palette above: a Go to Line panel
        // left open against a controller that just closed would be a stuck,
        // non-functional orphan pointing at an already-evicted editor store
        // (found by hostile review of PR #126).
        if goToLinePanel?.originController === controller {
            goToLinePanel?.close()
        }
        // Same reasoning again: a Quick Open panel left open against a
        // closed controller would point at an already-deallocated
        // `workspaceFileIndex`/`fileTreeModel`.
        if quickOpen?.originController === controller {
            quickOpen?.close()
        }
        scheduleSaveSession()
        updateKeyModel()
    }

    func addController(
        _ controller: WindowController,
        addingAsTab: Bool,
        keyWindow: NSWindow? = nil,
        useAmbientWindow: Bool = true
    ) {
        controllers.append(controller)

        let hostWindow = keyWindow ?? (useAmbientWindow ? NSApp.keyWindow : nil)
        if addingAsTab, let key = Self.tabHost(hostWindow), key != controller.window,
           let tab = controller.window {
            key.addTabbedWindow(tab, ordered: .above)
        }

        controller.showWindow(nil)
        scheduleSaveSession()
        updateKeyModel()
    }

    func updateKeyModel() {
        keyModel = currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow)?.model
        commandStateDidChange()
    }

    /// Resolve menu commands against a live document window. A dismissed
    /// panel may leave no key window without another document-key notification.
    /// A visible non-document key window is intentional and must not redirect
    /// Save or Export to a different document.
    func currentCommandController(keyWindow: NSWindow?, mainWindow: NSWindow?) -> WindowController? {
        if let keyWindow, let controller = controllers.first(where: { $0.window === keyWindow }) {
            return controller
        }
        guard keyWindow?.isVisible != true, let mainWindow else { return nil }
        return controllers.first(where: { $0.window === mainWindow })
    }

    /// Invalidates SwiftUI command validation after AppKit has processed an
    /// event that may have changed first responder or the key window.
    func commandStateDidChange() {
        commandStateRevision &+= 1
    }
}
