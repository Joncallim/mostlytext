import AppKit
import EditorCore
import FileCore
import FileTree
import Foundation
import Workspace

enum TerminationRecoveryPresentation {
    static let title = "Recovery Could Not Be Secured"
    static let message = "MacDown kept this window open because unsaved recovery data could not be verified. "
        + "Retry, or use Save As to preserve your changes."
    static let retryTitle = "Retry"
    static let saveAsTitle = "Save As…"
}

enum SessionSaveResult {
    case saved
    case recoveryFailed(WindowController)
    case sessionPublicationFailed
    /// Cleanup work is intentionally not serialized independently of the
    /// live document. Termination is blocked until its exact retry action has
    /// completed, so a relaunch cannot forget the action and retire the wrong
    /// lifetime.
    case pendingRecoveryCleanup(WindowController)

    var persisted: Bool {
        if case .saved = self {
            return true
        }
        return false
    }
}

private struct ControllerTabSnapshot {
    let controller: WindowController
    let tab: TabSnapshot
}

/// Captures one tab's document state while a window session is being saved.
/// Kept with the session-publication code so the coordinator's core type stays
/// focused on live window ownership.
struct TabSnapshot {
    let record: TabRecord
    let documentID: String
    let documentText: String
    let documentState: FileDocumentState
    let documentGeneration: UInt
    let documentRecoveryEpoch: UUID
}

/// Orders session publications by snapshot and invalidates snapshots when
/// session state changes, before the next debounced save begins (#183 F20).
struct SessionPublicationOrder {
    private var lastSnapshot: UInt64 = 0
    private var lastPublished: UInt64 = 0
    private var lastInvalidatedSnapshot: UInt64 = 0

    mutating func beginSnapshot() -> UInt64 {
        lastSnapshot += 1
        return lastSnapshot
    }

    mutating func invalidateCapturedSnapshots() {
        lastInvalidatedSnapshot = lastSnapshot
    }

    func isSuperseded(_ sequence: UInt64) -> Bool {
        sequence < lastSnapshot || sequence <= lastPublished || sequence <= lastInvalidatedSnapshot
    }

    mutating func markPublished(_ sequence: UInt64) {
        lastPublished = max(lastPublished, sequence)
    }
}

extension WindowCoordinator {
    /// ⌃⌘O (D11). Reveals the outline in the key window, then hands off to
    /// its `OutlineController` — focusing a hidden list is a dead shortcut,
    /// so both the sidebar and the outline's own disclosure are ensured open
    /// first. JSON documents route to the JSON outline channel.
    func focusOutline() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }) else { return }
        controller.model.sidebarVisible = true
        controller.model.setSectionExpanded(.outline, true)
        if controller.model.activeDocument?.format.id == "json" {
            controller.outlineController.requestJSONFocus()
        } else {
            controller.outlineController.requestFocus()
        }
    }

    /// Saves the current set of open documents as the session. Dirty documents
    /// are snapshotted before any `await` so recovery and session JSON remain
    /// consistent even while the main actor handles later user edits.
    @discardableResult
    func saveSession() async -> Bool {
        await saveSessionResult().persisted
    }

    /// `isAutosave` marks the debounced background save: it yields to a newer
    /// one (`scheduleSaveSession` cancels the older task), so after the awaited
    /// recovery work it must not publish its by-then obsolete snapshot over the
    /// newer session (#183 F20). Explicit callers (termination, Save As, rename)
    /// retry an invalidated snapshot once, then report a publication failure
    /// rather than claim success for an obsolete session.
    func saveSessionResult(
        allowingSaveAsPublicationFor publishingModel: WorkspaceModel? = nil,
        isAutosave: Bool = false
    ) async -> SessionSaveResult {
        for attempt in 0 ..< 2 {
            if let pendingController = controllers.first(where: {
                $0.model.hasPendingRecoveryCleanup && $0.model !== publishingModel
            }) {
                return .pendingRecoveryCleanup(pendingController)
            }
            let (snapshot, activeID) = sessionSnapshot()
            // Before the launch restore has consumed the saved session there are no windows to snapshot (a first-run
            // welcome window, say): publishing now would replace the saved tabs with an empty session and orphan their
            // recovery files. The saved session is still the truth, so leave it.
            if snapshot.isEmpty, let launch = launchSession, !launch.tabs.isEmpty {
                return .saved
            }
            let sequence = sessionPublicationOrder.beginSnapshot()
            if let failedController = await persistDirtyRecovery(in: snapshot) {
                return .recoveryFailed(failedController)
            }
            await afterSessionRecoveryPersisted?()
            if isAutosave, Task.isCancelled {
                return .saved
            }
            // Editor text can advance dirty -> dirty without scheduling a coordinator session save. Check the live
            // document lifetime and generation too, after recovery and before the synchronous canonical write.
            // Scheduling a changed session invalidates A while B is debounced.
            // Beginning B also invalidates A if B fails.
            let superseded = sessionPublicationOrder.isSuperseded(sequence)
            let documentChanged = (!superseded || afterSessionPublicationRejected != nil)
                && !capturedDocumentsRemainCurrent(snapshot)
            if superseded || documentChanged {
                afterSessionPublicationRejected?(superseded, documentChanged)
                if isAutosave {
                    return .saved
                }
                if attempt == 0 {
                    continue
                }
                return .sessionPublicationFailed
            }
            let session = WorkspaceSession(tabs: snapshot.map(\.tab.record), activeTabID: activeID)
            guard sessionStore.saveSessionVerified(session) else {
                if let controller = controllers.first {
                    return .recoveryFailed(controller)
                }
                return .sessionPublicationFailed
            }
            sessionPublicationOrder.markPublished(sequence)
            return .saved
        }
        return .sessionPublicationFailed
    }

    private func capturedDocumentsRemainCurrent(_ snapshot: [ControllerTabSnapshot]) -> Bool {
        let current = Self.inTabOrder(controllers, window: \.window).compactMap { controller in
            controller.model.tabStore.tabs.first.map { (controller, $0) }
        }
        guard current.count == snapshot.count else { return false }
        return zip(snapshot, current).allSatisfy { saved, live in
            let document = live.1.document
            return saved.controller === live.0
                && saved.tab.record.id == live.1.id
                && saved.tab.documentID == document.id
                && saved.tab.documentRecoveryEpoch == document.recoveryEpoch
                && saved.tab.documentGeneration == document.mutationGeneration
                && saved.tab.documentState == document.state
                && saved.tab.record.fileURL == document.fileURL
                && saved.tab.record.encoding == document.encoding
                && saved.tab.documentText.isExactlyEqual(to: document.text)
        }
    }

    private func sessionSnapshot() -> ([ControllerTabSnapshot], UUID?) {
        let snapshot = Self.inTabOrder(controllers, window: \.window)
            .compactMap { controller -> ControllerTabSnapshot? in
                guard let tab = controller.model.tabStore.tabs.first else { return nil }
                let system = controller.editorStore.existingSystem(for: tab.id.uuidString)
                // The editor's true primary selection, not AppKit's topmost range:
                // with several selections they differ (#183 F23).
                let selectedRange = system?.selectionSet.primaryRange
                let lexicalRoot = controller.model.folderURL
                let physicalRoot = lexicalRoot?.resolvingSymlinksInPath().standardizedFileURL
                let scope = physicalRoot.map(FolderAccessScope.init)
                let bookmark = physicalRoot.flatMap { try? $0.bookmarkData(options: .withSecurityScope) }
                    ?? tab.folderRootBookmark
                _ = scope
                return ControllerTabSnapshot(
                    controller: controller,
                    tab: TabSnapshot(
                        record: TabRecord(
                            id: tab.id,
                            fileURL: tab.document.fileURL,
                            untitledDocumentID: tab.document.fileURL == nil ? tab.document.id : nil,
                            documentRecoveryEpoch: tab.document.recoveryEpoch,
                            isPinned: tab.isPinned,
                            cursorPosition: selectedRange?.location,
                            selectionLength: selectedRange?.length,
                            scrollOffset: system.map { Double($0.scrollOffset) },
                            previewLayout: tab.previewLayout,
                            previewMode: tab.previewMode,
                            syntaxOverride: tab.syntaxOverride,
                            encoding: tab.document.encoding,
                            baseSHA256: tab.document.baselineSHA256,
                            folderRootBookmark: bookmark,
                            folderRootAlias: lexicalRoot ?? tab.folderRootAlias
                        ),
                        documentID: tab.document.id,
                        documentText: tab.document.text,
                        documentState: tab.document.state,
                        documentGeneration: tab.document.mutationGeneration,
                        documentRecoveryEpoch: tab.document.recoveryEpoch
                    )
                )
            }
        let activeID = Self.activeSessionItem(controllers, window: \.window, mainWindow: NSApp.mainWindow)?
            .model.tabStore.activeTabID
        return (snapshot, activeID)
    }

    private func persistDirtyRecovery(in snapshot: [ControllerTabSnapshot]) async -> WindowController? {
        for entry in snapshot where entry.tab.documentState == .dirty || entry.tab.documentState == .conflict {
            do {
                let persisted = try await recoveryBuffer.saveCurrentLifetime(
                    content: entry.tab.documentText,
                    for: entry.tab.documentID,
                    version: entry.tab.documentGeneration,
                    epoch: entry.tab.documentRecoveryEpoch
                )
                if !persisted {
                    // A rejection at this exact version is not necessarily a
                    // failure: an earlier debounced save (TabStore.persist)
                    // may already have written this identical snapshot, and
                    // the buffer correctly refuses to re-apply an
                    // already-recorded version (RecoveryBuffer.canApply).
                    // Only a write whose recorded content actually matches
                    // what we tried to save counts as secured; anything else
                    // (a stale/rejected write, or no record at all) is a real
                    // failure. Matches TabStore.saveSession()'s identical
                    // fallback for the same race.
                    guard let recovered = try? await recoveryBuffer.load(
                        for: entry.tab.documentID,
                        epoch: entry.tab.documentRecoveryEpoch
                    ), recovered.isExactlyEqual(to: entry.tab.documentText) else {
                        return entry.controller
                    }
                }
            } catch {
                return entry.controller
            }
        }
        return nil
    }

    /// Explicit UI seam for a rejected termination snapshot. The application
    /// remains running; the user can retry after a transient failure or choose
    /// Save As from the affected document window.
    func presentTerminationRecoveryRequired(for target: WindowController? = nil) {
        terminationRecoveryState = .recoveryRequired
        terminationRecoveryController = target
        guard let window = target?.window
            ?? controllers.first(where: { $0.window?.isKeyWindow == true })?.window
            ?? controllers.first?.window
        else { return }
        let alert = NSAlert()
        alert.messageText = TerminationRecoveryPresentation.title
        alert.informativeText = TerminationRecoveryPresentation.message
        alert.alertStyle = .critical
        alert.addButton(withTitle: TerminationRecoveryPresentation.retryTitle)
        alert.addButton(withTitle: TerminationRecoveryPresentation.saveAsTitle)
        alert.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if response == .alertFirstButtonReturn {
                    let retryTarget = target ?? terminationRecoveryController
                    await retryTarget?.model.retryRecoveryCleanup()
                    switch await saveSessionResult() {
                    case .saved:
                        terminationRecoveryState = .none
                        NSApp.terminate(nil)
                    case let .recoveryFailed(controller), let .pendingRecoveryCleanup(controller):
                        presentTerminationRecoveryRequired(for: controller)
                    case .sessionPublicationFailed:
                        presentTerminationRecoveryRequired()
                    }
                } else {
                    if let target {
                        await target.saveDocumentAs()
                    } else {
                        await controllers.first(where: { $0.window === window })?.saveDocumentAs()
                    }
                }
            }
        }
    }

    func handleTerminationSessionResult(_ persisted: Bool) -> Bool {
        guard !persisted else {
            terminationRecoveryState = .none
            terminationRecoveryController = nil
            return true
        }
        presentTerminationRecoveryRequired()
        return false
    }

    func handleTerminationSessionResult(_ result: SessionSaveResult) -> Bool {
        let controller: WindowController
        switch result {
        case .saved:
            terminationRecoveryState = .none
            terminationRecoveryController = nil
            return true
        case let .recoveryFailed(failedController), let .pendingRecoveryCleanup(failedController):
            controller = failedController
        case .sessionPublicationFailed:
            presentTerminationRecoveryRequired()
            return false
        }
        presentTerminationRecoveryRequired(for: controller)
        return false
    }

    /// Applies a workspace-owned preview layout to the key document.
    func setPreviewLayout(_ layout: PreviewLayoutMode) {
        guard let keyModel,
              let activeTabID = keyModel.tabStore.activeTabID
        else { return }
        keyModel.tabStore.setPreviewLayout(layout, for: activeTabID)
        scheduleSaveSession()
    }
}
