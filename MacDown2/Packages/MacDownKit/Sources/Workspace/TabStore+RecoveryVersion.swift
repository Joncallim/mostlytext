import FileCore
import Foundation

public extension TabStore {
    /// Reassert recovery for the exact tab/lifetime captured before an async cleanup.
    /// The tab may be inactive now; a closed or rebound tab must not be resurrected.
    func advancingRecoveryVersion(
        inTab tabID: UUID,
        documentID: String,
        epoch: UUID,
        after removedVersion: UInt
    ) -> FileDocument? {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              tab.document.id == documentID,
              tab.document.recoveryEpoch == epoch,
              tab.document.state != .clean
        else { return nil }
        let current = tab.document
        let durable = current.advancingRecoveryVersion(after: removedVersion)
        if durable.mutationGeneration != current.mutationGeneration {
            updateDocument(inTab: tabID) { _ in durable }
        }
        return durable
    }
}
