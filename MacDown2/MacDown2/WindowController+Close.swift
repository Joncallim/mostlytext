import AppKit
import FileCore
import Foundation

extension WindowController {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let coordinator, coordinator.controllers.contains(where: { $0 === self }) else { return true }
        // Workspace recovery cleanup owns an exact lifetime retry. Do not let
        // AppKit discard the window while that action is still the only safe
        // route to retire or remove its prior recovery state.
        guard !model.hasPendingRecoveryCleanup else { return false }
        // A second ⌘W (or the red button) while a sheet is up would stack another close sheet behind it.
        guard sender.attachedSheet == nil else { return false }
        guard let document = model.activeDocument else {
            coordinator.removeController(self)
            return true
        }
        if document.state == .clean {
            Task { @MainActor [weak self] in
                guard let self,
                      await (externalFileController.retireRecovery(
                          for: document,
                          resumeCloseOnSuccess: true
                      )).isAbsent
                else { return }
                await closeAfterRetire(of: document)
            }
            return false
        }
        let presentedContext = CloseSheetContext(document)
        if document.state == .conflict {
            presentConflictCloseSheet(for: sender)
            return false
        }
        presentDirtyCloseSheet(for: sender, context: presentedContext)
        return false
    }

    /// The backing file can disappear while the sheet is open. Describe the
    /// user's intent, not a destination decision made before they click.
    static func makeDirtyCloseAlert(fileName: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: "Unsaved Changes")
        alert.informativeText = String(
            localized: """
            Save changes to "\(fileName)"? If the original file is unavailable, \
            you may be asked to choose a location.
            """
        )
        alert.addButton(withTitle: String(localized: "Save Changes"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Discard Changes"))
        alert.alertStyle = .warning
        return alert
    }

    private func presentDirtyCloseSheet(for sender: NSWindow, context: CloseSheetContext) {
        let fileName = context.fileURL?.lastPathComponent ?? String(localized: "Untitled")
        let alert = Self.makeDirtyCloseAlert(fileName: fileName)
        alert.beginSheetModal(for: sender) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, coordinator != nil else { return }
                switch Self.dirtyCloseDisposition(response, current: model.activeDocument, context: context) {
                case .reevaluate:
                    _ = windowShouldClose(sender)
                case .save:
                    // Explicit-origin, not the ambient `saveDocument()` this
                    // used ambiguously resolve its Save As panel against
                    // `NSApp.keyWindow` — during a close sheet that is
                    // usually `sender`, but never provably so. Every other
                    // window-bound save path in this app was already fixed
                    // to route this way; this alert's Save button was the
                    // one place that hadn't been (#57).
                    if model.activeDocument?.state != .clean {
                        await saveDocumentFromExplicitOrigin()
                    }
                    if model.activeDocument?.state == .clean {
                        if let saved = model.activeDocument {
                            guard await (externalFileController.retireRecovery(
                                for: saved,
                                resumeCloseOnSuccess: true
                            )).isAbsent else { return }
                            await closeAfterRetire(of: saved)
                        }
                    }
                case let .discard(current):
                    guard await (externalFileController.retireRecovery(
                        for: current,
                        resumeCloseOnSuccess: true
                    )).isAbsent else { return }
                    await closeAfterRetire(of: current)
                case .cancel:
                    sender.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    private func presentConflictCloseSheet(for window: NSWindow) {
        guard let document = model.activeDocument else { return }
        let context = CloseSheetContext(document)
        let alert = NSAlert()
        alert.messageText = String(localized: "External File Change")
        alert.informativeText = String(
            localized: "The file changed on disk while this window has local edits. Choose which version to close."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Keep My Changes and Save"))
        alert.addButton(withTitle: String(localized: "Use Disk Version and Close"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, coordinator != nil,
                      let current = model.activeDocument,
                      current.state == .conflict
                else { return }
                guard matchesPresentedContext(current, context) else {
                    _ = windowShouldClose(window)
                    return
                }
                switch response {
                case .alertFirstButtonReturn:
                    await externalFileController.resolveConflict(.keepMine)
                    // Same explicit-origin fix as the dirty-close alert
                    // above (#57): this button's save should never resolve
                    // against whatever happens to be `NSApp.keyWindow`.
                    await saveDocumentFromExplicitOrigin()
                case .alertSecondButtonReturn:
                    await externalFileController.resolveConflict(.useExternal)
                default:
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                guard model.activeDocument?.state == .clean else { return }
                if let saved = model.activeDocument {
                    guard await (externalFileController.retireRecovery(
                        for: saved,
                        resumeCloseOnSuccess: true
                    )).isAbsent else { return }
                    await closeAfterRetire(of: saved)
                }
            }
        }
    }

    /// Every close path retires the document's recovery lifetime, which awaits I/O. Close only if the document is
    /// still what was retired: same recovery lifetime, text (exact scalars) and state. Text typed or a state change in
    /// that gap must not
    /// be discarded unprompted, so the normal close flow runs again and asks about whatever changed. A bare
    /// `mutationGeneration` bump (a background reconcile that changed neither) is not a reason to keep the window
    /// open: comparing it made the close flaky.
    ///
    /// The retired lifetime rejects every later recovery write, so a window kept open on it would lose its edits to a
    /// crash and fail the session autosave for every window: it is moved to a fresh persisted lifetime first.
    func closeAfterRetire(of document: FileDocument) async {
        guard let coordinator else { return }
        guard let active = model.activeDocument,
              active.id == document.id,
              active.recoveryEpoch == document.recoveryEpoch,
              active.state == document.state,
              active.text.isExactlyEqual(to: document.text)
        else {
            await model.renewRecoveryLifetime(retiredFrom: document)
            window?.performClose(nil)
            return
        }
        coordinator.removeController(self)
        close()
    }

    /// Whether the document is still what its close sheet asked about: same identity, URL, text (exact
    /// scalars), state and disk revisions. Like `closeAfterRetire`, a bare `mutationGeneration` bump is NOT a
    /// change — background reconciles advance it with none of the above moving while a sheet is up, which
    /// silently discarded the user's choice: "Use Disk Version and Close" left the window open with the local
    /// edits (generation 16 → 21, everything else identical; found by the first real run of
    /// `ExternalFileChangesUITests.testConflictCloseUseDiskClosesWithoutDiscardingTheExternalVersion`).
    func matchesPresentedContext(_ document: FileDocument, _ context: CloseSheetContext) -> Bool {
        Self.presentedContextMatches(document, context)
    }

    static func presentedContextMatches(_ document: FileDocument, _ context: CloseSheetContext) -> Bool {
        document.id == context.documentID
            && document.fileURL?.standardizedFileURL == context.fileURL
            && document.text.isExactlyEqual(to: context.text)
            && document.state == context.state
            && document.backingState == context.backingState
            && document.lastKnownRevision == context.lastKnownRevision
            && document.pendingExternalRevision == context.pendingExternalRevision
    }

    enum DirtyCloseDisposition {
        case save
        case discard(FileDocument)
        case cancel
        case reevaluate
    }

    /// Save Changes expresses intent, so a backing-state change alone must
    /// not reopen the sheet before the save can recheck the live destination.
    /// Discard remains strict: a vanished file may make this the last copy.
    static func dirtyCloseDisposition(
        _ response: NSApplication.ModalResponse,
        current: FileDocument?,
        context: CloseSheetContext
    ) -> DirtyCloseDisposition {
        if response == .alertSecondButtonReturn {
            return .cancel
        }
        guard let current else { return .reevaluate }
        switch response {
        case .alertFirstButtonReturn:
            let sameContent = current.id == context.documentID
                && current.recoveryEpoch == context.recoveryEpoch
                && current.fileURL?.standardizedFileURL == context.fileURL
                && current.text.isExactlyEqual(to: context.text)
                && (current.state == context.state || current.state == .clean)
            return sameContent ? .save : .reevaluate
        case .alertThirdButtonReturn:
            return current.recoveryEpoch == context.recoveryEpoch
                && presentedContextMatches(current, context) && current.state != .clean
                ? .discard(current) : .reevaluate
        default:
            return .cancel
        }
    }

    func completeCloseAfterRecoveryRetry(
        documentID: String,
        recoveryEpoch: UUID,
        mutationGeneration: UInt
    ) {
        guard let coordinator,
              let current = model.activeDocument,
              current.id == documentID,
              current.recoveryEpoch == recoveryEpoch,
              current.mutationGeneration == mutationGeneration
        else { return }
        coordinator.removeController(self)
        close()
    }
}

struct CloseSheetContext {
    let documentID: String
    let recoveryEpoch: UUID
    let fileURL: URL?
    let text: String
    let state: FileDocumentState
    /// A vanished backing file changes only this (and the generation): the sheet's "discard" would then discard the
    /// last copy, so the close flow must be re-run to offer Save a Copy.
    let backingState: FileBackingState
    let lastKnownRevision: FileRevision?
    let pendingExternalRevision: FileRevision?

    init(_ document: FileDocument) {
        documentID = document.id
        recoveryEpoch = document.recoveryEpoch
        fileURL = document.fileURL?.standardizedFileURL
        text = document.text
        state = document.state
        backingState = document.backingState
        lastKnownRevision = document.lastKnownRevision
        pendingExternalRevision = document.pendingExternalRevision
    }
}
