import AppKit
import FileCore
import Foundation

extension WindowCoordinator {
    /// Opens `url`, or activates the window that already shows it. Opens of the SAME file are
    /// serialised (`KeyedSerialRunner`), so a second request waits for the first and then finds
    /// its window instead of creating a duplicate document.
    func openDocument(
        at url: URL,
        folderRoot: URL? = nil,
        folderAccessURL: URL? = nil,
        folderSelectionURL: URL? = nil,
        folderRenameURL: URL? = nil,
        relativeTo overrideKeyWindow: NSWindow? = nil,
        encoding: FileEncodingMetadata? = nil,
        shouldContinue: (@MainActor () -> Bool)? = nil,
        useAmbientWindow: Bool = true,
        admitting: (@MainActor (WindowController) -> Bool)? = nil,
        failed: (@MainActor (FileStoreError) -> Void)? = nil
    ) async {
        let resolved = url.resolvingFinalSymlink()
        await documentOpens.run(key: Self.openSerializationKey(for: resolved)) { [self] in
            guard shouldContinue?() ?? true else { return }
            await performOpenDocument(
                at: resolved,
                folderRoot: folderRoot,
                folderAccessURL: folderAccessURL,
                folderSelectionURL: folderSelectionURL,
                folderRenameURL: folderRenameURL,
                relativeTo: overrideKeyWindow,
                encoding: encoding,
                shouldContinue: shouldContinue,
                useAmbientWindow: useAmbientWindow,
                admitting: admitting,
                failed: failed
            )
        }
    }

    private func liveController(for url: URL) -> WindowController? {
        guard let controller = controllerForDocument(url: url), controller.window != nil, !controller.isClosed else {
            return nil
        }
        return controller
    }

    /// Opens a file in a new window, or activates the existing window if the
    /// same file is already open. The single choke point every real file
    /// open routes through — see `WindowCoordinator+RecentFiles.swift` for
    /// why `recentFileDocuments.record(_:)` is called from here.
    /// - Parameter relativeTo: when non-`nil`, used as the tab host instead
    ///   of `NSApp.keyWindow` — the command palette (via `createInFolder`,
    ///   whose "New File" this backs) passes its captured origin window
    ///   here so the newly created document opens relative to it rather
    ///   than whatever window is key once this `await` resolves
    ///   (post-review finding #4).
    func performOpenDocument(
        at url: URL,
        folderRoot: URL? = nil,
        folderAccessURL: URL? = nil,
        folderSelectionURL: URL? = nil,
        folderRenameURL: URL? = nil,
        relativeTo overrideKeyWindow: NSWindow? = nil,
        encoding: FileEncodingMetadata? = nil,
        shouldContinue: (@MainActor () -> Bool)? = nil,
        useAmbientWindow: Bool = true,
        admitting: (@MainActor (WindowController) -> Bool)? = nil,
        failed: (@MainActor (FileStoreError) -> Void)? = nil
    ) async {
        guard shouldContinue?() ?? true else { return }
        // A link to a file opens (and saves to) that file; resolved first so the
        // same file is not opened twice, once through the link and once directly.
        let url = url.resolvingFinalSymlink()
        if let existing = liveController(for: url) {
            await focusAdmitted(existing, admitting: admitting) {
                await self.focus(
                    existing,
                    for: url,
                    folder: FolderOpenContext(
                        root: folderRoot,
                        accessURL: folderAccessURL,
                        selectionURL: folderSelectionURL,
                        renameURL: folderRenameURL
                    ),
                    encoding: encoding,
                    shouldContinue: shouldContinue
                )
            }
            return
        }
        let keyWindow = overrideKeyWindow ?? (useAmbientWindow ? NSApp.keyWindow : nil)
        let model = makeWindowModel()
        let outcome = await model.tabStore.openFileInTab(url, encoding: encoding)
        if shouldContinue != nil {
            await afterFolderSearchFileLoad?()
        }
        guard shouldContinue?() ?? true else { return }
        model.setFolderRoot(folderRoot)

        guard !model.tabStore.tabs.isEmpty else {
            if case let .failure(error) = outcome {
                reportOpenFailure(error, url: url, failed: failed)
            }
            return
        }
        let controller = makeWindowController(model: model)
        if let folderRoot {
            await controller.setFileTreeRoot(folderRoot, accessURL: folderAccessURL)
        }
        if shouldContinue != nil {
            await afterFolderSearchRootRebuild?()
        }
        guard shouldContinue?() ?? true else {
            controller.window?.close()
            return
        }
        controller.fileTreeModel.selectedURL = folderSelectionURL
        controller.fileTreeModel.renamingURL = folderRenameURL
        guard admitting?(controller) ?? true else { controller.window?.close(); return }
        addController(controller, addingAsTab: true, keyWindow: keyWindow, useAmbientWindow: useAmbientWindow)
        recentFileDocuments.record(url)
    }

    private func focusAdmitted(_ controller: WindowController,
                               admitting: (@MainActor (WindowController) -> Bool)?,
                               focus: @MainActor () async -> Void) async {
        guard admitting?(controller) ?? true else { return }
        await focus()
    }

    private func reportOpenFailure(_ error: FileStoreError, url: URL,
                                   failed: (@MainActor (FileStoreError) -> Void)?) {
        if let failed {
            failed(error)
        } else {
            presentOpenFailure(error, url: url)
        }
    }

    /// Identifies the FILE, not its spelling: a case variant, a different Unicode normalisation, or a
    /// symlinked parent directory names the same file, and two such opens must still queue
    /// behind one another. A file that does not exist yet falls back to its standardized path.
    static func openSerializationKey(for url: URL) -> String {
        let identity = PhysicalFileIdentity(url: url)
        if let id = identity.fileObjectID {
            return "file:\(id.volume):\(id.file)"
        }
        return "path:\(url.standardizedFileURL.path)"
    }
}
