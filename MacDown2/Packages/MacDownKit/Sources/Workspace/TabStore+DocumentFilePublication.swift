import Foundation

extension TabStore {
    /// Synchronous, read-only observation before any tab's backing-file
    /// identity becomes visible, including inactive and newly inserted tabs.
    public func setDocumentFilesWillPublish(_ callback: (@MainActor ([WorkspaceTab]) -> Void)?) {
        precondition(callback == nil || documentFilesWillPublish == nil, "Document file observer already installed")
        documentFilesWillPublish = callback
    }

    func notifyBeforeDocumentFilesPublication(_ incoming: [WorkspaceTab]) {
        guard let documentFilesWillPublish,
              tabs.count != incoming.count || zip(tabs, incoming).contains(where: { old, new in
                  old.id != new.id
                      || old.document.fileURL.map { Data($0.absoluteString.utf8) }
                      != new.document.fileURL.map { Data($0.absoluteString.utf8) }
                      || old.document.lastKnownRevision?.fileObjectID != new.document.lastKnownRevision?.fileObjectID
              })
        else { return }
        isNotifyingDocumentFilePublication = true
        defer { isNotifyingDocumentFilePublication = false }
        documentFilesWillPublish(incoming)
    }
}
