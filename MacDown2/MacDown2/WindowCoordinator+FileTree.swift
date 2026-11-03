import AppKit
import Foundation
import Workspace

extension WindowCoordinator {
    var keyFolderRoot: URL? {
        controllers.first(where: { $0.window == NSApp.keyWindow })?.fileTreeModel.root
    }

    /// `nil` whenever the active editor's text view is the current first
    /// responder, even if the sidebar still shows a selected file — the
    /// fix for a live Cmd-D conflict with Select Next/All Occurrence
    /// (§6.9, Slice 3c): before this, selecting a sidebar file and then
    /// clicking into the editor left every Folder command (bound off this
    /// property) still enabled, because only `fileTreeModel.selectedURL`
    /// was checked, never focus. Fixed at this property's own definition,
    /// not just at the "Duplicate" button's call site, since ALL THREE
    /// Folder commands read this one property, and Cmd-D was not the only
    /// live conflict with a key the editor itself depends on: "Rename" is a
    /// plain, unmodified Return, which the editor's own E10 list/blockquote-
    /// continuation assists use, and "Move to Trash" is Cmd-Delete, a
    /// standard `NSTextView` binding (delete to beginning of line) — both
    /// were silently hijack-able the identical way Cmd-D was, just never
    /// separately reported. Fixing at the source closes all three at once
    /// rather than only the one this slice's own issue named. Reads
    /// `commandStateRevision` to establish an Observation dependency on
    /// AppKit focus changes, exactly like `canPerformOccurrenceSelection`'s
    /// own inverted check (`WindowCoordinator+OccurrenceSelection.swift`) —
    /// the two properties are deliberately never simultaneously "occupied"
    /// for the same keystroke, so both bindings can stay declared on it.
    var keyFolderSelection: URL? {
        _ = commandStateRevision
        guard canPerformOccurrenceSelection == false,
              !Self.isTextEditing(NSApp.keyWindow?.firstResponder)
        else { return nil }
        return controllers.first(where: { $0.window == NSApp.keyWindow })?.fileTreeModel.selectedURL
    }

    /// Any text control being edited — the Find or folder-search field, the rename field, a palette
    /// field — owns Return, ⌘D and ⌘⌫ while it has focus; the Folder commands must not claim them.
    static func isTextEditing(_ responder: NSResponder?) -> Bool {
        responder is NSText
    }

    /// The key window's controller for a Folder command, unless a text control is being edited: the menu's enabled
    /// state can be stale (it refreshes on mouse/focus events), and Return/⌘D/⌘⌫ belong to the field.
    private func keyFolderCommandController() -> WindowController? {
        guard !Self.isTextEditing(NSApp.keyWindow?.firstResponder) else { return nil }
        return controllers.first(where: { $0.window == NSApp.keyWindow })
    }

    func renameKeyFolderSelection() {
        guard let controller = keyFolderCommandController(),
              let selected = controller.fileTreeModel.selectedURL else { return }
        controller.fileTreeModel.renamingURL = selected
    }

    func duplicateKeyFolderSelection() {
        guard let controller = keyFolderCommandController(),
              let selected = controller.fileTreeModel.selectedURL else { return }
        let context = controller.fileTreeModel.beginOperation()
        Task { @MainActor in
            do {
                _ = try await controller.fileTreeModel.duplicate(selected, context: context)
            } catch where controller.fileTreeModel.isCurrent(context) {
                controller.fileTreeModel.recordOperationError(error)
            } catch {}
        }
    }

    func trashKeyFolderSelection() {
        guard let controller = keyFolderCommandController(),
              let selected = controller.fileTreeModel.selectedURL,
              let window = controller.window else { return }
        let confirmation = FileTreeTrashConfirmation(
            model: controller.fileTreeModel, source: selected
        ) { [weak controller, weak window] in
            guard let controller, let window else { return false }
            return !controller.isClosed && controller.window === window
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Move \"\(selected.lastPathComponent)\" to Trash?")
        alert.informativeText = String(localized: "You can recover it from the Trash in Finder.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self, weak controller] response in
            guard response == .alertFirstButtonReturn, let self, let controller else { return }
            Task { @MainActor in
                do {
                    guard let result = try await confirmation.run() else { return }
                    self.documentFileWasDeleted(at: result.url)
                } catch where confirmation.isCurrent {
                    controller.fileTreeModel.recordOperationError(error)
                } catch {}
            }
        }
    }

    /// What ⌘N does. The standard New shortcut must never be dead: with a folder
    /// open it creates a file in that folder, and otherwise (a fresh launch has
    /// no folder) it opens a blank document, like ⌘T.
    enum NewFileTarget: Equatable {
        case fileInKeyFolder
        case blankDocument

        static func resolve(hasKeyFolder: Bool) -> Self {
            hasKeyFolder ? .fileInKeyFolder : .blankDocument
        }
    }

    func newFileCommand() {
        switch NewFileTarget.resolve(hasKeyFolder: keyFolderRoot != nil) {
        case .fileInKeyFolder: createInKeyFolder(isDirectory: false)
        case .blankDocument: newDocument()
        }
    }

    func createInKeyFolder(isDirectory: Bool) {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }) else { return }
        createInFolder(isDirectory: isDirectory, controller: controller)
    }

    /// Explicit-target variant of `createInKeyFolder(isDirectory:)`, used by
    /// the command palette so "New File" targets the window the palette was
    /// opened from (post-review finding #7) instead of resolving
    /// `NSApp.keyWindow` — the palette itself — at invocation time.
    func createInFolder(isDirectory: Bool, controller: WindowController) {
        guard let root = controller.fileTreeModel.root else { return }
        let context = controller.fileTreeModel.beginOperation()
        Task { @MainActor in
            do {
                let result = try await (isDirectory
                    ? controller.fileTreeModel.createFolder(in: root, context: context)
                    : controller.fileTreeModel.createFile(in: root, context: context))
                guard result.isCurrent else { return }
                let created = result.url
                controller.fileTreeModel.selectedURL = created
                controller.fileTreeModel.renamingURL = isDirectory ? created : nil
                if !isDirectory {
                    controller.fileTreeModel.pendingOpenURL = created
                    // Explicit target: without this, `openDocument`'s own
                    // internal `NSApp.keyWindow` read could resolve to
                    // whatever is key by the time this `await` completes —
                    // the command palette, if that's who called
                    // `createInFolder` (post-review finding #4) — rather
                    // than `controller`, which this whole operation is
                    // already scoped to.
                    await openDocument(
                        at: created,
                        folderRoot: root,
                        folderAccessURL: controller.fileTreeModel.rootAccessURL,
                        folderSelectionURL: created,
                        folderRenameURL: created,
                        relativeTo: controller.window
                    )
                    if controller.fileTreeModel.isCurrent(context), controller.fileTreeModel.root == root {
                        controller.fileTreeModel.pendingOpenURL = nil
                    }
                }
            } catch {
                if controller.fileTreeModel.isCurrent(context) {
                    controller.fileTreeModel.recordOperationError(error)
                }
            }
        }
    }

    /// Capture the originating document before scheduling or presenting a
    /// panel. With no document, acceptance creates a separate window; a later
    /// document cannot borrow that earlier application-level choice.
    @discardableResult
    func chooseFolder(relativeTo controller: WindowController? = nil,
                      using injectedPanel: (any FilePanelProviding)? = nil) -> Task<Void, Never> {
        let origin = controller ?? folderTargetController(createIfNeeded: false)
        let hadOrigin = origin != nil
        let provider = injectedPanel ?? origin.map { NSFilePanelProvider(window: $0.window) }
            ?? NSFilePanelProvider(applicationWindow: nil)
        return Task { @MainActor [weak self, weak origin] in
            guard !Task.isCancelled, let self else { return }
            if hadOrigin {
                guard let origin, !origin.isClosed, controllers.contains(where: { $0 === origin }) else { return }
            }
            guard let url = await provider.chooseFolder(), !Task.isCancelled else { return }
            if hadOrigin {
                guard let origin, !origin.isClosed, controllers.contains(where: { $0 === origin }) else { return }
                openFolder(url, in: origin)
            } else {
                newDocument()
                guard let created = controllers.last else { return }
                openFolder(url, in: created)
            }
        }
    }

    /// Opens a root in one window only; roots are intentionally per-window.
    /// - Parameter in: the window to open the root in, or `nil` to resolve
    ///   `NSApp.keyWindow` at call time (the real menu/recent-folder path,
    ///   invoked from that window already).
    func openFolder(_ url: URL, accessURL: URL? = nil, in controller: WindowController? = nil) {
        guard let controller = controller ?? folderTargetController() else { return }
        controller.model.setFolderRoot(url)
        recentFolderRoots.record(url)
        Task { await controller.setFileTreeRoot(url, accessURL: accessURL) }
        scheduleSaveSession()
    }

    func openRecentFolder(_ url: URL) {
        guard let resolution = recentFolderRoots.resolve(url) else {
            if recentFolderRoots.preservesUnavailableBookmarks {
                chooseFolder()
            }
            return
        }
        openFolder(resolution.lexicalURL, accessURL: resolution.accessURL)
    }

    func revealActiveFile() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              let url = controller.model.activeDocument?.fileURL else { return }
        controller.model.sidebarVisible = true
        controller.model.setSectionExpanded(.folder, true)
        Task {
            guard await !controller.fileTreeModel.reveal(url) else { return }
            presentRevealOutsideRootAlert(for: url, controller: controller)
        }
    }

    private func presentRevealOutsideRootAlert(for url: URL, controller: WindowController) {
        guard let window = controller.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "File Is Outside the Open Folder")
        alert.informativeText = String(localized: "Open its parent folder to reveal it in the sidebar?")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Open Parent Folder"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self, weak controller] response in
            guard response == .alertFirstButtonReturn, let self, let controller else { return }
            Task { @MainActor in
                let root = url.deletingLastPathComponent()
                controller.model.setFolderRoot(root)
                self.recentFolderRoots.record(root)
                await controller.setFileTreeRoot(root)
                _ = await controller.fileTreeModel.reveal(url)
                self.scheduleSaveSession()
            }
        }
    }

    func documentWasRenamed(from old: URL, to new: URL) async {
        var published = false
        for controller in controllers {
            guard await controller.model.tabStore.documentWasRenamed(from: old, to: new) else { continue }
            published = true
        }
        guard published else { return }
        remapFolderRootsAfterAcceptedMove(from: old, to: new)
    }

    /// A document identity is already durably migrated by the external-file
    /// controller. Propagate only the shared root/session identities; do not
    /// ask `TabStore` to migrate the same recovery lifetime again.
    func remapFolderRootsAfterAcceptedMove(from old: URL, to new: URL) {
        for controller in controllers {
            controller.model.remapFolderRoot(from: old, to: new)
            controller.fileTreeModel.itemWasRenamed(from: old, to: new)
            controller.externalFileController.synchronize(with: controller.model.activeDocument)
        }
        recentFolderRoots.remap(from: old, to: new)
        scheduleSaveSession()
    }

    func documentFileWasDeleted(at url: URL) {
        for controller in controllers {
            switch controller.model.tabStore.documentFileWasDeleted(at: url) {
            case .closedCleanTab:
                removeController(controller)
                controller.close()
            case let .needsPrompt(id):
                presentDeletedDocumentAlert(on: controller, tabID: id)
            case .notOpen:
                break
            }
        }
        scheduleSaveSession()
    }

    private func presentDeletedDocumentAlert(on controller: WindowController, tabID: UUID) {
        guard let window = controller.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "File Moved to Trash")
        alert.informativeText = String(localized: "This document has unsaved changes.")
        alert.addButton(withTitle: String(localized: "Save As…"))
        alert.addButton(withTitle: String(localized: "Close Without Saving"))
        alert.addButton(withTitle: String(localized: "Keep Open"))
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { [weak self, weak controller] response in
            Task { @MainActor in
                guard let self, let controller else { return }
                if response == .alertFirstButtonReturn {
                    controller.model.tabStore.activate(tabID)
                    await controller.saveDocumentAs()
                } else if response == .alertSecondButtonReturn {
                    await self.discardDeletedDocument(in: controller)
                }
            }
        }
    }

    /// "Close Without Saving" for a deleted document: the discarded text must also leave the
    /// recovery store, or a later session replay can resurrect it as a dirty tab.
    func discardDeletedDocument(in controller: WindowController) async {
        guard let document = controller.model.activeDocument else {
            removeController(controller)
            controller.close()
            return
        }
        guard await controller.externalFileController.retireRecovery(for: document).isAbsent else { return }
        await controller.closeAfterRetire(of: document)
    }
}
