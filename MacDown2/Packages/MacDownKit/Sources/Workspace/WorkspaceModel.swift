import FileCore
import Foundation
import Observation

/// Sidebar sections displayed in the workspace shell.
public enum SidebarSection: String, Sendable, CaseIterable, Identifiable {
    case folder
    case outline
    /// Folder-wide search (EPIC-22 §6.16, Slice 7b) — a persistent sidebar
    /// section rather than a floating panel like Quick Open/Command
    /// Palette, since a search session is browsed for far longer per
    /// invocation (the same reasoning §6.14 used for the current-document
    /// Find bar, applied one level further).
    case search

    public var id: String {
        rawValue
    }

    /// Order used on first launch and to fill gaps during reconciliation.
    public static var defaultOrder: [SidebarSection] {
        allCases
    }

    /// Drops unknown identifiers, appends missing cases in `allCases` order.
    public static func reconcile(_ stored: [String]) -> [SidebarSection] {
        var result: [SidebarSection] = []
        var seen: Set<String> = []
        for rawValue in stored {
            guard let section = SidebarSection(rawValue: rawValue),
                  seen.insert(section.id).inserted else { continue }
            result.append(section)
        }
        for section in SidebarSection.allCases where !seen.contains(section.id) {
            result.append(section)
        }
        return result
    }
}

/// Applies a SwiftUI `onMove`-style reorder and returns the new ordering.
///
/// `destination` follows the `ForEach.onMove` convention: it is an insertion
/// point expressed in the *pre-move* ordering, so sources that precede it are
/// discounted before the elements are re-inserted. Source indices outside
/// `elements` are ignored and `destination` is clamped, so a stale drag from a
/// view that has not yet observed a shorter list can never trap.
func reorder<Element>(
    _ elements: [Element],
    fromOffsets source: IndexSet,
    toOffset destination: Int
) -> [Element] {
    let valid = IndexSet(source.filter { elements.indices.contains($0) })
    let moved = valid.map { elements[$0] }
    var remaining = elements.enumerated()
        .filter { !valid.contains($0.offset) }
        .map(\.element)
    let clampedDestination = max(0, min(destination, elements.count))
    let precedingSources = valid.filter { $0 < clampedDestination }.count
    let insertionIndex = max(0, min(clampedDestination - precedingSources, remaining.count))
    remaining.insert(contentsOf: moved, at: insertionIndex)
    return remaining
}

/// The observable model behind the MacDown 2 workspace shell.
///
/// Responsibilities:
/// - Own the `TabStore` that tracks open tabs and the active document.
/// - Route File menu intents (`newDocument`, `openFile`, `save`, `close`, …).
/// - Expose command enablement state for SwiftUI `Commands`.
/// - Persist window UI state (sidebar visibility, section expansion).
/// - Coordinate session restore on first launch.
///
/// `WorkspaceModel` is `@MainActor` and lives in the SPM `Workspace` module.
/// The tab bar and other views live in the app target.
@MainActor
@Observable
public final class WorkspaceModel {
    /// The tab store that owns all open tabs.
    public let tabStore: TabStore
    let documentWriter = DocumentWriter()
    /// Test seam after the detached conflict read completes, including a failed read.
    var afterSaveConflictRead: (@Sendable () -> Void)?
    /// Test seam for a newer outcome after conflict recovery persistence but before error publication.
    var afterSaveConflictRecoveryPersistence: (@MainActor () async -> Void)?
    var nextSaveGeneration: UInt = 0
    var latestSaveGenerationByDocumentID: [String: UInt] = [:]
    /// A Save As owns the old document lane until its publication has either
    /// rebound the active descendant or failed. Ordinary saves arriving in
    /// that interval are deliberately coalesced instead of writing the old
    /// pathname after Save As has selected a destination.
    var inFlightSaveAsByDocumentID: [String: UInt] = [:]
    /// Reserve the destination picker before an async command can be fired
    /// again. This is distinct from the Saving indicator, which begins only
    /// after a destination has been accepted.
    var saveAsAdmissions: [SavingDocumentLifetime: UUID] = [:]
    /// Active logical saves retain exact document lifetimes. Save As adds its
    /// destination lifetime before the tab changes identity; overlapping
    /// saves remain independent and the destination picker is not a write.
    var activeSaveOperations: [LogicalSaveOperationID: Set<SavingDocumentLifetime>] = [:]
    /// Test seam for the crash window after destination session publication
    /// and before a dirty Save As acknowledges its source redirect.
    var onSaveAsDestinationSessionPublished: (@MainActor (FileDocument, FileDocument) async -> Void)?
    /// Test seam for a local edit arriving while dirty Save As recovery is
    /// finalizing. Production leaves this unset.
    var onSaveAsRecoveryFinalized: (@MainActor () async -> Void)?
    /// Former lifetimes whose post-Save As retirement needs an explicit retry
    /// after a destination session was already published. This is a set, not
    /// a single slot: a later Save As must not overwrite older cleanup work.
    var pendingRecoveryCleanupActions: Set<PendingRecoveryCleanupAction> = []
    var pendingSaveAsRecoveryContinuations: [PendingRecoveryCleanupAction: SaveAsRecoveryContinuation] = [:]
    /// The app owns the canonical multi-window session file. A window-local
    /// `TabStore` may intentionally use a no-op store, so dirty Save As must
    /// await this boundary before it acknowledges the recovery redirect.
    var saveAsSessionPublisher: (@MainActor () async -> Bool)?

    /// Whether a recovery-cleanup Retry has exact Save As lifetimes to retire.
    public var hasPendingRecoveryCleanup: Bool {
        !pendingRecoveryCleanupActions.isEmpty
    }

    /// Installs the app-owned publication boundary used by dirty Save As.
    /// Window-local tab stores can deliberately be no-ops because the native
    /// window coordinator owns the canonical multi-window session file.
    public func setSaveAsSessionPublisher(_ publisher: @escaping @MainActor () async -> Bool) {
        saveAsSessionPublisher = publisher
    }

    /// Test seam for cancellation between recovery-lifetime minting and
    /// publication of a new untitled tab.
    public var onManagedDocumentLifetimePrepared: (@MainActor @Sendable () async -> Void)?

    /// Asks the host whether another window already has `url` open; Save As refuses such a name.
    public var isOpenInAnotherWindow: (@MainActor (URL) -> Bool)?

    /// Called after a save or Save As published `url` on disk.
    public var onDocumentWritten: (@MainActor (URL) -> Void)?
    /// Test seam: runs after a recovery-retry step finished persisting a replacement, before it revalidates and
    /// publishes it (#183 F01 — the awaited persistence is a suspension point at which the user can edit).
    var afterRecoveryRetryPersistence: (@MainActor () async -> Void)?

    /// The document currently shown in the content area.
    public var activeDocument: FileDocument? {
        tabStore.activeDocument
    }

    /// The folder opened via ⌘⇧O, if any. The actual folder tree UI is E09.
    public private(set) var folderURL: URL? {
        willSet {
            if folderURL != newValue {
                folderAssociationWillChange?()
            }
        }
    }

    @ObservationIgnored var folderAssociationWillChange: (@MainActor () -> Void)?

    /// Keeps the per-window folder association aligned with an in-app folder
    /// rename without changing a lexical URL that is outside that subtree.
    public func remapFolderRoot(from old: URL, to new: URL) {
        guard let folderURL else { return }
        let oldComponents = old.standardizedFileURL.pathComponents
        let components = folderURL.standardizedFileURL.pathComponents
        guard components.starts(with: oldComponents) else { return }
        let suffix = components.dropFirst(oldComponents.count).joined(separator: "/")
        self.folderURL = suffix.isEmpty
            ? new.standardizedFileURL
            : new.appendingPathComponent(suffix, isDirectory: true).standardizedFileURL
    }

    /// The most recent error surfaced to the user. Views may present this.
    public internal(set) var lastError: WorkspaceError? {
        didSet { errorRevision &+= 1 }
    }

    /// Bumped on every `lastError` assignment; see `WorkspaceModel+ErrorOwnership.swift`.
    @ObservationIgnored var errorRevision: UInt64 = 0

    /// True from the moment `newManagedDocument` starts until its tab is
    /// published. The window is shown before this resolves (`WindowCoordinator
    /// .newDocument(addAsTab:)` adds the controller synchronously, before
    /// awaiting), so without this a view has no way to distinguish "no
    /// document, press ⌘N" from "the ⌘N you just pressed hasn't landed yet."
    public internal(set) var isCreatingDocument = false

    /// Whether the sidebar column is visible in THIS window. Persisted via
    /// `stateStore` (so a new window's initial visibility follows the most
    /// recently closed one), but deliberately per-window while a window is
    /// actually open — `WindowCoordinatorPaletteOriginTargetingTests
    /// .toggleSidebarFromAnExplicitOriginTogglesOnlyThatOriginsSidebar`
    /// already pins this: showing/hiding the column in one window must not
    /// yank it out from under another window's user. This is unlike
    /// `sectionOrder`/`sectionExpanded` below, which #34 is specifically
    /// about making consistent live across windows — visibility and layout
    /// are different kinds of state even though they share a persistence
    /// suite. Not broadcast.
    public var sidebarVisible: Bool {
        didSet {
            guard sidebarVisible != oldValue else { return }
            stateStore.sidebarVisible = sidebarVisible
        }
    }

    /// Document-order of sidebar sections. Persisted via `stateStore`.
    /// `internal(set)`, not `private(set)`: the setter is used by
    /// `WorkspaceModel+SidebarLayout.swift` (a different file, so `private`
    /// would not reach it) — still not settable outside this module.
    public internal(set) var sectionOrder: [SidebarSection]

    /// Cached expansion state so SwiftUI body evaluations do not hit
    /// `UserDefaults` on every read. Not `private`: read/written by
    /// `WorkspaceModel+SidebarLayout.swift`, split out to stay under the
    /// file_length lint budget (matches `WorkspaceModel+Saving.swift`'s same
    /// reason).
    var sectionExpanded: [SidebarSection: Bool]

    public var hasActiveDocument: Bool {
        tabStore.hasActiveDocument
    }

    /// `true` if the active document can be saved right now.
    public var canSave: Bool {
        tabStore.canSave
    }

    /// `true` while a save write for the *active* document is genuinely in
    /// flight (#57). Views use this to show that Save is working rather than
    /// looking hung — previously there was no observable signal at all, so a
    /// save that took a moment looked identical to the app not responding.
    public var isSavingActiveDocument: Bool {
        guard let document = tabStore.activeDocument else { return false }
        let lifetime = SavingDocumentLifetime(document)
        return activeSaveOperations.values.contains { $0.contains(lifetime) }
    }

    /// `true` if the active tab exists and is not pinned.
    public var canClose: Bool {
        tabStore.canCloseActiveTab
    }

    /// Not `private`: read/written by `WorkspaceModel+SidebarLayout.swift`.
    var stateStore: WorkspaceStateStoring
    /// Fans this window's sidebar-layout edits out to every other open
    /// window sharing the same `stateStore` suite, and applies theirs back
    /// (#34). `nil` for every existing call site that does not pass one
    /// (all unit tests, and any standalone `WorkspaceModel`) — behaviour is
    /// then identical to before this type existed. Only `WindowCoordinator`
    /// constructs one shared instance and passes it to every window.
    let layoutBroadcaster: SidebarLayoutBroadcaster?
    let panel: any FilePanelProviding

    public init(
        tabStore: TabStore? = nil,
        stateStore: WorkspaceStateStoring = WorkspaceStateStore(),
        layoutBroadcaster: SidebarLayoutBroadcaster? = nil,
        panel: (any FilePanelProviding)? = nil
    ) {
        self.tabStore = tabStore ?? TabStore()
        self.stateStore = stateStore
        self.layoutBroadcaster = layoutBroadcaster
        self.panel = panel ?? NoOpFilePanelProvider()
        folderURL = nil
        lastError = nil
        sidebarVisible = stateStore.sidebarVisible
        sectionOrder = SidebarSection.reconcile(stateStore.sidebarSectionOrder)
        sectionExpanded = Dictionary(uniqueKeysWithValues: SidebarSection.allCases.map { section in
            (section, stateStore.sidebarSectionExpanded[section.rawValue] ?? true)
        })
        layoutBroadcaster?.subscribe(self)
    }

    // MARK: - Intents

    /// Creates a new untitled tab with a Markdown document.
    public func newDocument() {
        tabStore.newTab()
        lastError = nil
    }

    /// Production new-document path. It observes the durable recovery ledger
    /// before publishing the untitled lifetime, unlike the synchronous
    /// compatibility helper retained for pure state tests and previews.
    ///
    /// `encoding` seeds the new document's `FileEncodingMetadata` — the App
    /// target passes the Formats pane's preference here; every other caller
    /// (tests, the synchronous `newDocument()`) keeps today's UTF-8 default.
    @discardableResult
    public func newManagedDocument(
        encoding: FileEncodingMetadata = .utf8Default,
        shouldPublish: @escaping @MainActor () -> Bool = { true }
    ) async -> Bool {
        isCreatingDocument = true
        defer { isCreatingDocument = false }
        do {
            let document = try await FileDocument.create(encoding: encoding, recoveryBuffer: tabStore.recoveryBuffer)
            await onManagedDocumentLifetimePrepared?()
            guard !Task.isCancelled, shouldPublish() else { return false }
            tabStore.newTab(document: document)
            lastError = nil
            return true
        } catch {
            lastError = .recoveryCleanupRequired(URL(fileURLWithPath: "Recovery"))
            return false
        }
    }

    /// Opens an existing file chosen by the user into a new tab, or activates
    /// the existing tab if the file is already open.
    public func openFile() async {
        let errorRevisionAtStart = errorRevision
        guard let url = await panel.chooseFile() else { return }
        switch await tabStore.openFileInTab(url) {
        case .success:
            clearLastError(ifUnchangedSince: errorRevisionAtStart)
        case let .failure(underlying):
            lastError = .openFailed(underlying: underlying)
        }
    }

    /// Opens a folder chosen by the user.
    public func openFolder() async {
        guard let url = await panel.chooseFolder() else { return }
        setFolderRoot(url)
    }

    /// Sets this window's folder root without showing a panel.
    public func setFolderRoot(_ url: URL?) {
        folderURL = url?.standardizedFileURL
    }

    /// Begins closing the active tab.
    public func requestCloseDocument() {
        guard pendingRecoveryCleanupActions.isEmpty else {
            lastError = .recoveryCleanupRequired(
                activeDocument?.fileURL ?? URL(fileURLWithPath: "Recovery")
            )
            return
        }
        tabStore.requestCloseActiveTab()
    }

    /// Resolves a dirty-close prompt for the active tab.
    public func resolveClose(_ resolution: CloseResolution) async {
        // The prompt is about the PENDING tab, which a batch close or a tab switch after the request can leave
        // inactive; save, Save As and discard all act on the active tab, so make the pending one active first.
        if let pending = tabStore.pendingCloseTabID, pending != tabStore.activeTabID {
            tabStore.activate(pending)
        }
        let closingDocument = tabStore.activeDocument
        guard pendingRecoveryCleanupActions.isEmpty else {
            lastError = .recoveryCleanupRequired(closingDocument?.fileURL ?? URL(fileURLWithPath: "Recovery"))
            return
        }
        if resolution == .discard, let closingDocument {
            let cleanup = await closingDocument.recoveryBuffer.retireWithOutcome(
                for: closingDocument.id,
                epoch: closingDocument.recoveryEpoch
            )
            guard cleanup.isAbsent else {
                registerPendingRecovery(.retire(for: closingDocument))
                await preserveOpenDocumentAfterFailedCloseRetirement(closingDocument)
                lastError = recoveryCleanupWorkspaceError(cleanup, document: closingDocument)
                return
            }
        }
        // Judge the save and the close against the CLOSING tab, not whichever tab is active once the save returns:
        // the user can switch tabs while it is writing, and a failed save must not close (or retire the recovery of)
        // the unsaved tab because a clean one is now active. The tab id survives a Save As rebind.
        let closingTabID = tabStore.activeTabID
        await tabStore.resolveClose(resolution) { [weak self] in
            await self?.saveInternalForClose()
            return self?.tabStore.tabs.first { $0.id == closingTabID }?.document.state == .clean
        }
        if let closingDocument {
            await retireRecoveryIfClosed(closingDocument, tabID: closingTabID)
        }
    }

    func recoveryCleanupWorkspaceError(
        _ outcome: RecoveryCleanupResult,
        document: FileDocument
    ) -> WorkspaceError {
        guard case let .failed(error) = outcome else {
            return .recoveryCleanupRequired(document.fileURL ?? URL(fileURLWithPath: document.id))
        }
        switch error {
        case let .markerWriteFailed(url, _), let .removalFailed(url, _), let .writeFailed(url, _),
             let .verificationFailed(url):
            return .recoveryCleanupRequired(url)
        }
    }
}
