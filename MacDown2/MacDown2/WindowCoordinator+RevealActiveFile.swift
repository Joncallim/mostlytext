import AppKit
import FileTree
import Foundation
import Workspace

/// The UI request's tab, recovery lifetime and folder choice at admission.
/// Revisions also reject a switch away and back to the same visible identity.
@MainActor
struct RevealRequestAuthority {
    let url: URL
    let identity: ActiveDocumentIdentity
    let activeIdentityRevision: UInt
    let folderURL: URL?
    let folderAssociationRevision: UInt
    let context: FileTreeOperationContext

    init?(for url: URL, controller: WindowController) {
        guard let identity = controller.model.tabStore.activeDocumentIdentity,
              identity.fileURL?.standardizedFileURL == url.standardizedFileURL else { return nil }
        self.url = url
        self.identity = identity
        activeIdentityRevision = controller.model.tabStore.activeIdentityRevision
        folderURL = controller.model.folderURL
        folderAssociationRevision = controller.model.folderAssociationRevision
        context = controller.fileTreeModel.beginOperation()
    }
}

extension WindowCoordinator {
    func revealActiveFile() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              let url = controller.model.activeDocument?.fileURL,
              let window = controller.window,
              let request = RevealRequestAuthority(for: url, controller: controller) else { return }
        controller.model.sidebarVisible = true
        controller.model.setSectionExpanded(.folder, true)
        Task { @MainActor [weak self, weak controller, weak window] in
            guard let self, let controller, let window else { return }
            guard await !controller.fileTreeModel.reveal(url, shouldSelect: {
                self.revealRequestIsCurrent(request, controller: controller, window: window)
            }) else { return }
            guard revealRequestIsCurrent(request, controller: controller, window: window) else { return }
            // A missing or unreadable entry inside the current root is not an outside-root request.
            if let root = request.folderURL?.standardizedFileURL,
               url.standardizedFileURL.pathComponents.starts(with: root.pathComponents) {
                return
            }
            presentRevealOutsideRootAlert(request, controller: controller, window: window)
        }
    }

    func revealRequestIsCurrent(
        _ request: RevealRequestAuthority, controller: WindowController, window: NSWindow
    ) -> Bool {
        controllers.contains(where: { $0 === controller })
            && !controller.isClosed && controller.window === window
            && controller.fileTreeModel.isCurrent(request.context)
            && controller.model.tabStore.activeDocumentIdentity == request.identity
            && controller.model.tabStore.activeIdentityRevision == request.activeIdentityRevision
            && controller.model.folderURL?.standardizedFileURL == request.folderURL?.standardizedFileURL
            && controller.model.folderAssociationRevision == request.folderAssociationRevision
    }

    private func presentRevealOutsideRootAlert(
        _ request: RevealRequestAuthority, controller: WindowController, window: NSWindow
    ) {
        let alert = NSAlert()
        alert.messageText = String(localized: "File Is Outside the Open Folder")
        alert.informativeText = String(localized: "Open its parent folder to reveal it in the sidebar?")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Open Parent Folder"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self, weak controller] response in
            guard response == .alertFirstButtonReturn, let self, let controller else { return }
            Task { @MainActor in
                guard self.revealRequestIsCurrent(request, controller: controller, window: window) else { return }
                let root = request.url.deletingLastPathComponent()
                let expectedRequest = controller.workspaceRootRequestGeneration &+ 1
                controller.model.setFolderRoot(root)
                let openedFolderRevision = controller.model.folderAssociationRevision
                self.recentFolderRoots.record(root)
                await controller.setFileTreeRoot(root)
                guard !controller.isClosed,
                      controller.workspaceRootRequestGeneration == expectedRequest,
                      controller.fileTreeModel.root == root.standardizedFileURL,
                      controller.model.tabStore.activeDocumentIdentity == request.identity,
                      controller.model.tabStore.activeIdentityRevision == request.activeIdentityRevision,
                      controller.model.folderAssociationRevision == openedFolderRevision,
                      controller.model.folderURL?.standardizedFileURL == root.standardizedFileURL,
                      let openedRequest = RevealRequestAuthority(for: request.url, controller: controller)
                else { return }
                _ = await controller.fileTreeModel.reveal(request.url, shouldSelect: {
                    self.revealRequestIsCurrent(openedRequest, controller: controller, window: window)
                        && controller.workspaceRootRequestGeneration == expectedRequest
                })
                self.scheduleSaveSession()
            }
        }
    }
}
