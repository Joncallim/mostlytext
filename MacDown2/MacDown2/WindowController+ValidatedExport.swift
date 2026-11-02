import ExportService
import Foundation

final class WeakValidatedExportLease {
    weak var lease: ExportLifetimeLease?

    init(_ lease: ExportLifetimeLease) {
        self.lease = lease
    }
}

extension WindowController {
    /// Called at command dispatch, before a panel can suspend or focus can move.
    /// This path is deliberately disconnected from the ordinary export command.
    func captureValidatedExportOrigin() -> ValidatedExportOrigin? {
        guard !isClosed, let tabID = model.tabStore.activeTabID,
              let document = model.activeDocument, document.format.id == "markdown"
        else { return nil }
        let lease = makeExportLifetimeLease()
        return ValidatedExportOrigin(
            controller: self, tabID: tabID, documentID: document.id,
            recoveryEpoch: document.recoveryEpoch, fileURL: document.fileURL,
            lease: lease
        )
    }

    /// Ordinary and optional validated exports share the same document-lifetime
    /// revocation points; this creates no alternate rendering activation path.
    func makeExportLifetimeLease() -> ExportLifetimeLease {
        let lease = ExportLifetimeLease()
        validatedExportLeases.removeAll { $0.lease == nil }
        validatedExportLeases.append(WeakValidatedExportLease(lease))
        return lease
    }

    func revokeValidatedExports() {
        for entry in validatedExportLeases {
            entry.lease?.revoke()
        }
        validatedExportLeases.removeAll()
    }
}

/// One window/document lifetime captured before panel presentation. A fresh
/// document value is frozen only after the panel returns; later editor changes
/// cannot alter that value, while identity replacement and close revoke its lease.
@MainActor
final class ValidatedExportOrigin {
    private weak var controller: WindowController?
    private let tabID: UUID
    private let documentID: String
    private let recoveryEpoch: UUID
    private let fileURL: URL?
    let lease: ExportLifetimeLease

    init(controller: WindowController, tabID: UUID, documentID: String,
         recoveryEpoch: UUID, fileURL: URL?, lease: ExportLifetimeLease) {
        self.controller = controller
        self.tabID = tabID
        self.documentID = documentID
        self.recoveryEpoch = recoveryEpoch
        self.fileURL = fileURL
        self.lease = lease
    }

    func freezeRequest() throws -> ExportRequest {
        try lease.checkActive()
        guard let controller, !controller.isClosed,
              controller.model.tabStore.activeTabID == tabID,
              let document = controller.model.activeDocument,
              document.id == documentID,
              document.recoveryEpoch == recoveryEpoch,
              document.fileURL == fileURL,
              document.format.id == "markdown"
        else {
            lease.revoke()
            throw CancellationError()
        }
        return ExportRequest(
            text: document.text, sourceGeneration: document.mutationGeneration,
            theme: controller.themeController.current, documentURL: document.fileURL
        )
    }

    func finish() {
        lease.revoke()
    }
}
