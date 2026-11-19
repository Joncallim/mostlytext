import FileCore
import Foundation

@MainActor
extension WorkspaceModel {
    /// A close path retired `document`'s recovery lifetime, but the document was edited during the retire and stays
    /// open. That lifetime now rejects every recovery write, so move the live document to a fresh one. The renewal is
    /// rebased onto the LIVE document in its original tab and published before it is persisted: text typed during
    /// either await is kept, and switching tabs cannot leave that document on a retired recovery lifetime.
    public func renewRecoveryLifetime(retiredFrom document: FileDocument) async {
        guard let tabID = tabRetainingLifetime(of: document)?.id,
              let epoch = try? await document.recoveryBuffer.mintRecoveryEpoch(),
              let live = tabStore.tabs.first(where: { $0.id == tabID })?.document,
              live.id == document.id, live.recoveryEpoch == document.recoveryEpoch else { return }
        let replacement = live.withReplacementRecoveryLifetime(epoch)
        tabStore.updateDocument(inTab: tabID) { _ in replacement }
        // A clean document has nothing to recover; a record for it would never be removed and a relaunch after the
        // file changed would restore it as a false conflict.
        if replacement.state != .clean {
            _ = await replacement.persistRecovery()
        }
    }

    /// After a close attempt: retire the closing document's recovery unless its tab is still open on the same
    /// lifetime (a failed Save-and-close keeps the unsaved tab and its recovery).
    func retireRecoveryIfClosed(_ closingDocument: FileDocument, tabID: UUID?) async {
        let retained = tabStore.tabs.first { $0.id == tabID }
            .map { isSameDocumentLifetime($0.document, closingDocument) }
        guard retained != true else { return }
        let cleanup = await closingDocument.recoveryBuffer.retireWithOutcome(
            for: closingDocument.id,
            epoch: closingDocument.recoveryEpoch
        )
        if !cleanup.isAbsent {
            registerPendingRecovery(.retire(for: closingDocument))
            lastError = recoveryCleanupWorkspaceError(cleanup, document: closingDocument)
        }
    }

    /// A failed retirement may have written the durable stale-write fence before its cleanup marker failed. Keep the
    /// tab open on a new managed lifetime so future edits and relaunch recovery never depend on that ambiguous one.
    /// Like `renewRecoveryLifetime`, the new lifetime is rebased onto the LIVE document and published before it is
    /// persisted, so text typed during either await is kept rather than replaced by an older copy. A tab switch
    /// while the recovery actor runs does not change which open document needs the new lifetime.
    func preserveOpenDocumentAfterFailedCloseRetirement(_ document: FileDocument) async {
        guard let tabID = tabRetainingLifetime(of: document)?.id,
              let epoch = try? await document.recoveryBuffer.mintRecoveryEpoch(),
              let live = tabStore.tabs.first(where: { $0.id == tabID })?.document,
              live.id == document.id,
              live.recoveryEpoch == document.recoveryEpoch else { return }
        let replacement = live.withReplacementRecoveryLifetime(epoch)
        tabStore.updateDocument(inTab: tabID) { _ in replacement }
        // A clean document has nothing to recover; a record for it would never be removed and a relaunch after the
        // file changed would restore it as a false conflict.
        if replacement.state != .clean {
            _ = await replacement.persistRecovery()
        }
    }

    private func tabRetainingLifetime(of document: FileDocument) -> WorkspaceTab? {
        tabStore.tabs.first {
            $0.document.id == document.id && $0.document.recoveryEpoch == document.recoveryEpoch
        }
    }
}
