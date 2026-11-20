import AppKit
import FileCore
import Foundation

struct FolderOpenContext {
    let root: URL?
    let accessURL: URL?
    let selectionURL: URL?
    let renameURL: URL?
}

extension WindowCoordinator {
    /// Opening a file that is already open focuses its window. When a specific
    /// encoding was asked for, the document is re-read with it through the
    /// window's own reopen path, which guards unsaved changes.
    func focus(
        _ existing: WindowController,
        for url: URL,
        folder: FolderOpenContext,
        encoding: FileEncodingMetadata?,
        shouldContinue: (@MainActor () -> Bool)? = nil
    ) async {
        guard shouldContinue?() ?? true else { return }
        guard let coordinator = existing.coordinator,
              coordinator.controllers.contains(where: { $0 === existing }),
              !existing.isClosed,
              let window = existing.window
        else { return }
        if let root = folder.root, existing.fileTreeModel.root == nil {
            existing.model.setFolderRoot(root)
            let association = existing.model.folderAssociationRevision
            let rootRequest = existing.workspaceRootRequestGeneration &+ 1
            let pendingRoot = existing.enqueueFileTreeRoot(root, accessURL: folder.accessURL)
            await pendingRoot.value
            guard shouldContinue?() ?? true,
                  existing.workspaceRootRequestGeneration == rootRequest,
                  existing.model.folderAssociationRevision == association,
                  existing.model.folderURL?.standardizedFileURL == root.standardizedFileURL,
                  existing.fileTreeModel.root == root.standardizedFileURL
            else { return }
        }
        guard shouldContinue?() ?? true,
              coordinator.controllers.contains(where: { $0 === existing }),
              !existing.isClosed,
              existing.window === window
        else { return }
        existing.fileTreeModel.selectedURL = folder.selectionURL
        existing.fileTreeModel.renamingURL = folder.renameURL
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
        recentFileDocuments.record(url)
        if let encoding {
            guard shouldContinue?() ?? true else { return }
            await existing.reopenDocument(withEncoding: encoding.encoding)
        }
    }
}
