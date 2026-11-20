import Workspace

/// A delayed document command belongs to the tab and recovery lifetime visible
/// when the user chose it. The revision also rejects switch-away-and-back ABA.
@MainActor
struct DocumentActionAuthority {
    let identity: ActiveDocumentIdentity
    let activeIdentityRevision: UInt

    init?(model: WorkspaceModel) {
        guard let identity = model.tabStore.activeDocumentIdentity else { return nil }
        self.identity = identity
        activeIdentityRevision = model.tabStore.activeIdentityRevision
    }

    func isCurrent(in controller: WindowController) -> Bool {
        !controller.isClosed
            && controller.coordinator?.controllers.contains(where: { $0 === controller }) == true
            && controller.model.tabStore.activeDocumentIdentity == identity
            && controller.model.tabStore.activeIdentityRevision == activeIdentityRevision
    }
}
