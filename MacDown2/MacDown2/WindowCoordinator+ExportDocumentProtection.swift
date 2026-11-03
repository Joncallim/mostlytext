import ExportService
import Workspace

extension WindowCoordinator {
    func protectExportsBeforePublishing(_ incoming: [WindowController]) {
        for controller in incoming {
            protectExportsBeforePublishing(controller.model.tabStore.tabs)
        }
    }

    func protectExportsBeforePublishing(_ incoming: [WorkspaceTab]) {
        exportDocumentProtections.documentsWillPublish(
            urls: incoming.compactMap(\.document.fileURL),
            identities: incoming.compactMap { ExportProtectedFileIdentity(document: $0.document) }
        )
    }
}
