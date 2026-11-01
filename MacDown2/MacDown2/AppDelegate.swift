import AppKit
import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
import Themes
import Workspace

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var coordinator: WindowCoordinator!
    private(set) var themeController: ThemeController!
    private(set) var themeCatalog: ThemeCatalogModel!
    private(set) var grammarRegistry: GrammarRegistry!
    private(set) var fileTreePreferences: FileTreePreferences!
    private(set) var recentFolderRoots: RecentFolderRoots!
    private(set) var recentFileDocuments: RecentFileDocuments!
    private(set) var appSettings: AppSettingsModel!
    private let sessionStore: WorkspaceSessionStoring
    private let recoveryBuffer: RecoveryBuffer
    private let workspaceStateStore: any WorkspaceStateStoring
    private let launchURLs: [URL]
    private let launchFolderURL: URL?
    private var hasPendingDocumentOpen = false
    private let defaults: UserDefaults
    private let shouldShowFirstRun: Bool
    private static let hasCompletedFirstRunKey = "com.joncallim.macdown2.hasCompletedFirstRun"

    override init() {
        Self.validateUITestLaunch()
        let args = Self.launchArguments
        let isUITesting = args.contains("-UITesting")

        // EPIC-22/#150: MacDown2Tests (non-UI app-target tests) is
        // intentionally serial-only -- see SingleTestInstanceGuard's own
        // doc comment for the full root-cause writeup. A no-op for a normal
        // launch, for `-UITesting` (its own separate isolation below already
        // applies), and for a genuinely single, correctly-serial test run.
        if !isUITesting {
            SingleTestInstanceGuard.enforceSingleInstance()
        }

        let defaults: UserDefaults
        if isUITesting {
            let sessionDir = Self.sessionDirectory(from: args)
            defaults = Self.prepareUITestState(sessionDirectory: sessionDir)
            sessionStore = WorkspaceSessionStore(fileURL: sessionDir.appendingPathComponent("session.json"))
            recoveryBuffer = RecoveryBuffer(
                recoveryDirectory: sessionDir.appendingPathComponent("recovery", isDirectory: true)
            )
            workspaceStateStore = WorkspaceStateStore(defaults: defaults)
        } else {
            sessionStore = WorkspaceSessionStore()
            recoveryBuffer = .shared
            defaults = .standard
            workspaceStateStore = WorkspaceStateStore()
        }

        self.defaults = defaults
        // Under `-UITesting`, `defaults` is always a fresh, empty, isolated
        // suite (above), so it would never report first-run as complete and
        // every one of this target's ~30 existing UI tests would otherwise
        // have to contend with an unexpected welcome window. Onboarding is
        // opted into explicitly with `-ForceFirstRun` instead, so its own UI
        // test can exercise it without disturbing every other one.
        shouldShowFirstRun = isUITesting
            ? args.contains("-ForceFirstRun")
            : !defaults.bool(forKey: Self.hasCompletedFirstRunKey)

        launchURLs = Self.openFilesPaths(from: args).map { URL(fileURLWithPath: $0) }
        launchFolderURL = Self.openFolderPath(from: args).map { URL(fileURLWithPath: $0, isDirectory: true) }
        themeController = ThemeController(preferenceStore: UserDefaultsThemePreferenceStore(defaults: defaults))
        themeCatalog = Self.makeThemeCatalog(controller: themeController, args: args)
        grammarRegistry = GrammarRegistry()
        fileTreePreferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        recentFolderRoots = RecentFolderRoots(preferences: fileTreePreferences)
        recentFileDocuments = RecentFileDocuments(preferences: fileTreePreferences)
        appSettings = AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults))
        super.init()
        connectThemeAppearanceOverride()

        coordinator = WindowCoordinator(
            sessionStore: sessionStore,
            panelProvider: NSFilePanelProvider(),
            recoveryBuffer: recoveryBuffer,
            themeController: themeController,
            grammarRegistry: grammarRegistry,
            fileTreePreferences: fileTreePreferences,
            recentFolderRoots: recentFolderRoots,
            recentFileDocuments: recentFileDocuments,
            appSettings: appSettings,
            workspaceStateStore: workspaceStateStore
        )
    }

    private static func makeThemeCatalog(controller: ThemeController, args: [String]) -> ThemeCatalogModel {
        let location: ThemeCatalogModel.Location = args.contains("-UITesting")
            ? .isolatedSession(sessionDirectory(from: args)) : .applicationSupport
        return ThemeCatalogModel(controller: controller, location: location)
    }

    func applicationDidFinishLaunching(_: Notification) {
        themeCatalog.start()
        NSWindow.allowsAutomaticWindowTabbing = true
        applyThemeAppearanceOverride()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        // Close any placeholder SwiftUI windows so we can manage document
        // windows ourselves. The `WindowGroup { EmptyView() }` scene creates
        // one or more windows that do not have a `WindowController` delegate.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            for window in NSApp.windows where Self.isSwiftUIPlaceholder(window) {
                window.close()
            }
        }

        if shouldShowFirstRun, launchURLs.isEmpty, launchFolderURL == nil {
            coordinator.showFirstRunWindow { [weak self] openedDocument in
                guard let self else { return }
                defaults.set(true, forKey: Self.hasCompletedFirstRunKey)
                proceedWithNormalLaunch(documentAlreadyOpened: openedDocument)
            }
        } else {
            proceedWithNormalLaunch()
        }
    }

    /// Windows the app itself manages — document windows and the first-run
    /// welcome window — are never placeholders. Closing the welcome window here
    /// would run its `windowWillClose`, marking first run complete before the
    /// user ever saw it.
    static func isSwiftUIPlaceholder(_ window: NSWindow) -> Bool {
        !(window.delegate is WindowController) && !(window.delegate is FirstRunWindowController)
    }

    /// The app's ordinary launch behavior: open files/folders passed on the
    /// command line, start a new document, or restore the prior session.
    /// Runs on every launch except a first-ever one, where it instead runs
    /// once the first-run welcome window is dismissed.
    ///
    /// `documentAlreadyOpened` is true when that welcome window's choice has
    /// already opened a document: launch then does not open an untitled
    /// document of its own (the saved session, if any, is still restored).
    private func proceedWithNormalLaunch(documentAlreadyOpened: Bool = false) {
        if !launchURLs.isEmpty {
            Task { @MainActor in
                await coordinator.restoreUnsavedSessionTabs()
                for url in launchURLs {
                    await coordinator.openDocument(at: url)
                }
                if let launchFolderURL {
                    coordinator.openFolder(launchFolderURL)
                }
            }
        } else if let launchFolderURL {
            Task { @MainActor in
                await coordinator.restoreUnsavedSessionTabs()
                await coordinator.ensureWindowExistsForReopen()
                coordinator.openFolder(launchFolderURL)
            }
        } else if appSettings.general.launchBehavior == .startWithNewDocument {
            if !documentAlreadyOpened {
                coordinator.newDocument()
            }
            Task { @MainActor in await coordinator.restoreUnsavedSessionTabs() }
        } else {
            // Scheduled synchronously so the tracked restore task exists before
            // any reopen event can be handled; the grace delay inside gives
            // `application(_:openFiles:)` a few run-loop ticks to arrive first.
            // A document the welcome window already opened must not discard a real saved session (only the empty-
            // session fallback, which would add a second Untitled tab, is skipped).
            coordinator.scheduleSessionRestore(createsUntitledWhenEmpty: !documentAlreadyOpened) { [weak self] in
                self?.hasPendingDocumentOpen ?? false
            }
        }
    }

    @objc private func systemAppearanceChanged() {
        guard themeController.appearanceMode == .system else { return }
        syncThemeAppearance()
    }

    private func connectThemeAppearanceOverride() {
        themeController.appearanceModeDidChange = { [weak self] _ in
            self?.applyThemeAppearanceOverride()
        }
    }

    private func applyThemeAppearanceOverride() {
        switch themeController.appearanceMode {
        case .system:
            NSApp.appearance = nil
            syncThemeAppearance()
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func syncThemeAppearance() {
        themeController.setAppearance(NSApp.effectiveAppearance.themeAppearance)
    }

    func applicationWillTerminate(_: Notification) {
        themeCatalog.cancel()
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            let result = await coordinator.saveSessionForTermination()
            let terminate = coordinator.handleTerminationSessionResult(result)
            if terminate {
                await themeCatalog.shutdown()
            }
            NSApp.reply(toApplicationShouldTerminate: terminate)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in
                await coordinator.ensureWindowExistsForReopen()
            }
        }
        // False: the coordinator handles the reopen itself. Returning true let SwiftUI's
        // WindowGroup also create its (empty) placeholder window — the launch-time cleanup
        // that closes those runs only once — so a Dock click left a stray blank window
        // beside the document window.
        return false
    }

    func application(_: NSApplication, openFiles filenames: [String]) {
        // AppKit also routes bare launch-argument paths (such as the
        // `-sessionDir` value under UI testing) and folder drops through this
        // handler. Only regular files count as document opens; anything else
        // must not suppress the session restore.
        let fileURLs = filenames
            .map { URL(fileURLWithPath: $0).resolvingFinalSymlink() }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
        guard !fileURLs.isEmpty else { return }
        hasPendingDocumentOpen = true
        Task { @MainActor in
            await coordinator.settleLaunchRestoration()
            for url in fileURLs {
                await coordinator.openDocument(at: url)
            }
        }
    }

    // MARK: - Launch argument parsing

    /// The arguments the test hooks (`-UITesting`, `-sessionDir`, `-openFiles`, `-openFolder`) are read from.
    /// Debug builds only, except the separately flagged and explicitly launched
    /// #117 native acceptance build. An ordinary Release build rejects a
    /// UI-test request before selecting stores instead of ignoring its isolation.
    static var launchArguments: [String] {
        #if ISSUE117_NATIVE_ACCEPTANCE
            let args = ProcessInfo.processInfo.arguments
            precondition(
                args.contains("-Issue117Acceptance") && args.contains("-UITesting")
                    && args.contains("-sessionDir") && args.contains("-openFiles"),
                "Launch the isolated #117 acceptance build with its retained launcher"
            )
            return args
        #elseif DEBUG
            ProcessInfo.processInfo.arguments
        #else
            []
        #endif
    }

    private static func sessionDirectory(from args: [String]) -> URL {
        if let index = args.firstIndex(of: "-sessionDir"), index + 1 < args.count {
            return URL(fileURLWithPath: args[index + 1])
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func openFilesPaths(from args: [String]) -> [String] {
        if let index = args.firstIndex(of: "-openFiles"), index + 1 < args.count {
            let remainder = args[index + 1]
            return remainder.split(separator: ",", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        if let arg = args.first(where: { $0.hasPrefix("-openFiles") }) {
            let prefix = "-openFiles"
            let remainder = String(arg.dropFirst(prefix.count))
            return remainder.split(separator: ",", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        return []
    }

    /// UI-test hook: `-fileMonitorDebounceMs <n>` (with `-UITesting`, Debug only via `launchArguments`) lengthens
    /// the external-file monitor's debounce, so a UI test can act on a conflict banner after deleting the backing
    /// file but before the monitor itself notices the deletion — otherwise the default 150 ms debounce always
    /// beats XCUITest's ~300 ms click and that action's own "file vanished" path can never be reached.
    /// `nil` (the monitor's own default) for every other launch.
    static var uiTestingFileMonitorDebounce: Duration? {
        let args = launchArguments
        guard args.contains("-UITesting"),
              let index = args.firstIndex(of: "-fileMonitorDebounceMs"), index + 1 < args.count,
              let milliseconds = Int(args[index + 1]), milliseconds >= 0
        else { return nil }
        return .milliseconds(milliseconds)
    }

    private static func openFolderPath(from args: [String]) -> String? {
        guard let index = args.firstIndex(of: "-openFolder"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

extension NSAppearance {
    var themeAppearance: ThemeAppearance {
        if bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .dark
        }
        return .light
    }
}
