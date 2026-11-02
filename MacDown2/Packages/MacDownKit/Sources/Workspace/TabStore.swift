import FileCore
import Foundation
import Observation

/// One open tab.
///
/// `id` is a stable UUID assigned at creation and used for session restore.
/// It is intentionally separate from `document.id` (the file URL string for
/// file-backed documents and the recovery key for untitled documents) so the
/// session schema stays stable across save-as and untitled recovery buffer keys.
public struct WorkspaceTab: Identifiable, Sendable {
    public let id: UUID
    public var document: FileDocument {
        didSet {
            // A Save As / rename into another format ends the override for
            // good, so returning to the original format later cannot revive it.
            if syntaxOverride != nil, oldValue.format.id != document.format.id {
                syntaxOverride = nil
            }
        }
    }

    public var isPinned: Bool

    /// Transient editor state captured at session-save time. Applied by the
    /// app target after restore; not used by `TabStore` itself.
    ///
    /// `cursorPosition` is the UTF-16 offset of the start of the editor
    /// selection (the caret when `selectionLength` is zero). `selectionLength`
    /// is the number of UTF-16 code units selected. Together they reconstruct
    /// the full `NSRange` on restore.
    public var cursorPosition: Int?
    public var selectionLength: Int?
    public var scrollOffset: Double?

    /// The editor/preview layout for this tab. Persisted with the session
    /// because it is part of the document workspace, not global UI state.
    public var previewLayout: PreviewLayoutMode?

    /// The preview pane's display mode for this tab (e.g. HTML source vs
    /// rendered), or `nil` to use the format's default mode. Persisted with
    /// the session; Save As format transitions invalidate it (the view resets
    /// it to `nil` when the format's capability changes).
    public var previewMode: PreviewMode?

    /// The user's explicit Syntax Mode for this tab, or `nil` to follow the
    /// file's format. Persisted with the session. Cleared when `document`'s
    /// format id changes; `SyntaxModeOverride.baseFormatID` additionally makes
    /// a stale override inert.
    public var syntaxOverride: SyntaxModeOverride?

    /// The format whose grammar and editing profile drive the editor.
    public var syntaxFormat: FileFormat {
        Self.registry.syntaxFormat(for: document.format, override: syntaxOverride)
    }

    private static let registry = FileFormatRegistry()

    /// Per-window folder root persisted alongside this native-window tab.
    public var folderRootBookmark: Data?
    public var folderRootAlias: URL?

    public init(
        id: UUID = UUID(),
        document: FileDocument,
        isPinned: Bool = false,
        cursorPosition: Int? = nil,
        selectionLength: Int? = nil,
        scrollOffset: Double? = nil,
        previewLayout: PreviewLayoutMode? = nil,
        previewMode: PreviewMode? = nil,
        syntaxOverride: SyntaxModeOverride? = nil,
        folderRootBookmark: Data? = nil,
        folderRootAlias: URL? = nil
    ) {
        self.id = id
        self.document = document
        self.isPinned = isPinned
        self.cursorPosition = cursorPosition
        self.selectionLength = selectionLength
        self.scrollOffset = scrollOffset
        self.previewLayout = previewLayout
        self.previewMode = previewMode
        self.syntaxOverride = syntaxOverride
        self.folderRootBookmark = folderRootBookmark
        self.folderRootAlias = folderRootAlias
    }
}

public enum DeletedDocumentOutcome: Sendable, Equatable {
    case notOpen
    case closedCleanTab(UUID)
    case needsPrompt(UUID)
}

/// The identity of the document currently exposed by one tab store. The tab UUID matters even when two tabs
/// happen to refer to the same file and recovery lifetime: a preview grant never follows a tab switch.
public struct ActiveDocumentIdentity: Equatable, Sendable {
    public let tabID: UUID
    public let documentID: String
    public let recoveryEpoch: UUID
    public let fileURL: URL?

    init(tab: WorkspaceTab) {
        tabID = tab.id
        documentID = tab.document.id
        recoveryEpoch = tab.document.recoveryEpoch
        fileURL = tab.document.fileURL
    }
}

/// In-app tab state: ordered tabs, active tab, dirty-close prompts, and session
/// persistence.
///
/// `TabStore` is `@MainActor` because it is observed by SwiftUI and because
/// `WorkspaceSessionStoring` implementations are main-actor isolated.
@MainActor
@Observable
public final class TabStore {
    /// All open tabs, ordered left-to-right. Pinned tabs always precede
    /// unpinned tabs.
    public internal(set) var tabs: [WorkspaceTab] {
        willSet {
            precondition(!isNotifyingActiveIdentityChange && !isNotifyingDocumentFilePublication,
                         "Identity publication callback cannot mutate TabStore")
            notifyBeforeDocumentFilesPublication(newValue)
            notifyBeforeActiveIdentityChange(from: activeIdentity(in: tabs, selectedBy: activeTabID),
                                             to: activeIdentity(in: newValue, selectedBy: activeTabID))
        }
    }

    /// The tab currently shown in the content area.
    public internal(set) var activeTabID: UUID? {
        willSet {
            precondition(!isNotifyingActiveIdentityChange && !isNotifyingDocumentFilePublication,
                         "Identity publication callback cannot mutate TabStore")
            notifyBeforeActiveIdentityChange(from: activeIdentity(in: tabs, selectedBy: activeTabID),
                                             to: activeIdentity(in: tabs, selectedBy: newValue))
        }
    }

    @ObservationIgnored private var activeIdentityWillChange: (@MainActor (
        ActiveDocumentIdentity?, ActiveDocumentIdentity?
    ) -> Void)?
    @ObservationIgnored private var isNotifyingActiveIdentityChange = false
    @ObservationIgnored var documentFilesWillPublish: (@MainActor ([WorkspaceTab]) -> Void)?
    @ObservationIgnored var isNotifyingDocumentFilePublication = false

    /// Non-nil while the dirty-close alert should be shown for this tab.
    public internal(set) var pendingCloseTabID: UUID?

    /// The active tab, if any.
    public var activeTab: WorkspaceTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    /// The document of the active tab, if any.
    public var activeDocument: FileDocument? {
        activeTab?.document
    }

    public var hasActiveDocument: Bool {
        activeTab != nil
    }

    /// `true` if the active document can be saved right now.
    public var canSave: Bool {
        guard let document = activeDocument else { return false }
        if document.state == .conflict {
            return false
        }
        if document.fileURL == nil {
            return !document.text.isEmpty
        }
        switch document.backingState {
        case .available, .unavailable:
            return document.state == .dirty
        case .untitled:
            return !document.text.isEmpty
        }
    }

    /// `true` if the active tab exists and is not pinned.
    public var canCloseActiveTab: Bool {
        guard let activeTab, !activeTab.isPinned else { return false }
        return true
    }

    let sessionStore: WorkspaceSessionStoring
    let recoveryBuffer: RecoveryBuffer
    var closeQueue: [UUID]
    var saveTask: Task<Void, Never>?
    var lastPublishedSession: WorkspaceSession?
    var hasRestoredSession = false
    var openRequestGeneration: UInt = 0
    /// Test seam inside the detached detection operation; production leaves this unset.
    var beforeAutomaticEncodingDetection: (@Sendable () -> Void)?
    /// Test seam for an edit arriving after a rename's managed epoch is
    /// prepared but before the batch captures a replacement snapshot.
    var onRenameReplacementPrepared: (@MainActor (FileDocument) async -> Void)?
    /// Test seam for an edit after a dirty tab's recovery migration completes
    /// but before the batch may publish its prepared replacement.
    var onRenameRecoveryMigrationCompleted: (@MainActor (FileDocument) async -> Void)?
    /// Test seam for a race while a stale source is being preserved after a
    /// recovery migration. Production leaves this unset.
    var onRenamePreservationPrepared: (@MainActor (FileDocument) async -> Void)?
    /// The native-window coordinator owns the canonical multi-window session
    /// file. It installs this verified publication boundary for renames.
    var renameSessionPublisher: (@MainActor () async -> Bool)?

    public init(
        sessionStore: WorkspaceSessionStoring = WorkspaceSessionStore(),
        recoveryBuffer: RecoveryBuffer = .shared
    ) {
        self.sessionStore = sessionStore
        self.recoveryBuffer = recoveryBuffer
        tabs = []
        activeTabID = nil
        pendingCloseTabID = nil
        closeQueue = []
        lastPublishedSession = nil
    }

    public func setRenameSessionPublisher(_ publisher: @escaping @MainActor () async -> Bool) {
        renameSessionPublisher = publisher
    }

    /// Called synchronously before a changed active document or tab identity becomes observable. The callback
    /// must not mutate this tab store or suspend; preview owners use it to revoke old admission immediately.
    public func setActiveIdentityWillChange(
        _ callback: (@MainActor (ActiveDocumentIdentity?, ActiveDocumentIdentity?) -> Void)?
    ) {
        precondition(callback == nil || activeIdentityWillChange == nil, "Active identity observer already installed")
        activeIdentityWillChange = callback
    }

    private func activeIdentity(in tabs: [WorkspaceTab], selectedBy tabID: UUID?) -> ActiveDocumentIdentity? {
        guard let tabID, let tab = tabs.first(where: { $0.id == tabID }) else { return nil }
        return ActiveDocumentIdentity(tab: tab)
    }

    private func notifyBeforeActiveIdentityChange(
        from old: ActiveDocumentIdentity?, to new: ActiveDocumentIdentity?
    ) {
        guard old != new, let activeIdentityWillChange else { return }
        isNotifyingActiveIdentityChange = true
        defer { isNotifyingActiveIdentityChange = false }
        activeIdentityWillChange(old, new)
    }

    // MARK: - Lifecycle intents

    /// Creates a new Markdown tab and activates it.
    ///
    /// The optional `id` and `document` are used by session restore so the
    /// restored tab keeps its original UUID and loaded document.
    public func newTab(id: UUID? = nil, document: FileDocument? = nil) {
        let tab = WorkspaceTab(
            id: id ?? UUID(),
            document: document ?? FileDocument(recoveryBuffer: recoveryBuffer)
        )
        tabs.append(tab)
        activeTabID = tab.id
        persist()
    }

    // MARK: - Document write-back

    /// Applies a transform to the active document and writes the returned value
    /// back. `FileDocument` is a value type; mutations return new instances.
    /// Applies a transform to the document of a specific tab, active or not. Used where an operation owns a document
    /// lifetime that the user may have switched away from.
    func updateDocument(inTab tabID: UUID, _ transform: (FileDocument) -> FileDocument) {
        guard let index = tabIndex(of: tabID) else { return }
        tabs[index].document = transform(tabs[index].document)
        persist()
    }

    public func updateActiveDocument(_ transform: (FileDocument) -> FileDocument) {
        guard let activeTabID, let index = tabIndex(of: activeTabID) else { return }
        tabs[index].document = transform(tabs[index].document)
        persist()
    }

    // MARK: - Session persistence

    /// Restores the prior session once. Missing files drop tabs; corrupt JSON
    /// yields an empty session. Never throws and never blocks launch.
    public func restoreSessionIfNeeded() async {
        guard !hasRestoredSession else { return }
        hasRestoredSession = true

        guard let session = sessionStore.loadSession() else { return }
        guard session.version == WorkspaceSession.currentVersion else { return }

        var restoredTabs: [WorkspaceTab] = []
        for record in session.tabs {
            if let tab = await restoreTab(from: record) {
                restoredTabs.append(tab)
            }
        }

        tabs = restoredTabs

        if let activeTabID = session.activeTabID, tabs.contains(where: { $0.id == activeTabID }) {
            self.activeTabID = activeTabID
        } else if let first = tabs.first {
            activeTabID = first.id
        } else {
            activeTabID = nil
        }

        await acknowledgePendingRecoveryMigrations()
        await saveSession()
    }

    /// Autosaves every dirty tab's text before publishing session identities.
    /// `.promptingClose` counts as dirty here too — `requestClose(_:)` calls
    /// `persist()` the moment a tab enters that state, so this is the
    /// autosave that is supposed to protect its edits while the close prompt
    /// is up and undecided.
    /// If recovery cannot be verified, the prior on-disk session remains the
    /// last-good session rather than pointing at an unrecoverable lifetime.
    @discardableResult
    public func saveSession() async -> Bool {
        for tab in tabs
            where tab.document.state == .dirty || tab.document.state == .conflict
            || tab.document.state == .promptingClose {
            // Snapshot before suspension. Besides keeping recovery I/O off the
            // observed main-actor store, this prevents a borrowed array entry
            // from crossing the actor hop while a later edit replaces it.
            let content = String(tab.document.text)
            let documentID = String(tab.document.id)
            let generation = tab.document.mutationGeneration
            let lifetime = tab.document.recoveryEpoch
            let recoveryBuffer = tab.document.recoveryBuffer
            let persistenceTask: Task<Bool, Never> = Task.detached(priority: .utility) {
                do {
                    return try await recoveryBuffer.saveCurrentLifetime(
                        content: content,
                        for: documentID,
                        version: generation,
                        epoch: lifetime
                    )
                } catch {
                    return false
                }
            }
            let persisted = await persistenceTask.value
            if !persisted {
                // A migration may have already written this exact immutable
                // snapshot at the same version. It is safe to publish only
                // when the recovery record still verifies the captured text;
                // a stale/rejected write never gets this exception.
                guard let recovered = try? await recoveryBuffer.load(for: documentID, epoch: lifetime),
                      recovered.isExactlyEqual(to: content)
                else { return false }
            }
        }
        let session = currentSession()
        sessionStore.saveSession(session)
        lastPublishedSession = session
        return true
    }
}
