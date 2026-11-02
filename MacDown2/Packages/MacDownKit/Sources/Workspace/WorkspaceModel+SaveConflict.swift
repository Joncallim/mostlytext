import FileCore
import Foundation

struct SaveConflictRetry {
    let isRetry: Bool
    let destinationPolicy: WorkspaceModel.SaveDestinationPolicy
    let encodingOverride: FileEncodingMetadata?
    let operation: LogicalSaveOperationID
}

@MainActor
extension WorkspaceModel {
    func reconcileSaveConflict(
        for document: FileDocument,
        context: SaveContext,
        retry: SaveConflictRetry
    ) async -> NonPromptingSaveResult {
        // A failed older write cannot start new recovery after a newer save or a different document lifetime.
        guard isLatestSave(context), let tabID = owningTabID(of: document),
              let captured = tabStore.tabs.first(where: { $0.id == tabID })?.document,
              let url = captured.fileURL
        else { return .handled }
        let result = await readConflictSnapshot(captured, at: url)
        guard isLatestSave(context), owningTabID(of: captured) == tabID,
              let current = tabStore.tabs.first(where: { $0.id == tabID })?.document
        else { return .handled }
        // Local typing (including edit/undo) retains its baseline. Reconcile against that live text, never
        // replace it with the captured text. An external baseline/encoding/destination change supersedes this read.
        guard hasSameConflictReadBaseline(current, captured) else { return .handled }
        guard current.state == captured.state || current.state == .dirty || current.state == .promptingClose else {
            return .handled
        }
        guard case let .success(snapshot) = result else {
            lastError = .unresolvedExternalConflict
            return .handled
        }
        let reconciliation = current.reconcilingExternalSnapshot(snapshot)
        tabStore.updateDocument(inTab: tabID) { _ in reconciliation.document }
        if reconciliation.document.state == .conflict {
            _ = await reconciliation.document.persistRecovery()
            await afterSaveConflictRecoveryPersistence?()
            guard isLatestSave(context), owningTabID(of: reconciliation.document) == tabID,
                  let latest = tabStore.tabs.first(where: { $0.id == tabID })?.document,
                  sameSaveAsSnapshot(latest, reconciliation.document),
                  hasSameConflictReadBaseline(latest, reconciliation.document)
            else { return .handled }
            lastError = .unresolvedExternalConflict
            return .handled
        }
        // `.promptingClose` reconciles the same as `.dirty` here (E18: a
        // metadata-only change preserves both states rather than collapsing
        // them). Excluding it would let `saveInternalForClose()` return
        // without ever reaching `.clean`; the close flow then treats that as
        // a failed save and silently reverts to `.dirty` with the prompt
        // dismissed — save-and-close would do nothing and say nothing.
        // An encoding change is a request to rewrite the file even when the
        // text is unedited, so a clean document must still retry it rather
        // than end silently with the old bytes.
        let hasEncodingChange = retry.encodingOverride.map { $0 != reconciliation.document.encoding } ?? false
        guard reconciliation.document.state == .dirty || reconciliation.document.state == .promptingClose
            || hasEncodingChange
        else {
            return .handled
        }
        guard !retry.isRetry else {
            // Something is touching this file's metadata faster than one
            // retry can keep up with. Stop instead of recursing indefinitely,
            // and say so rather than leaving the document dirty with no
            // explanation.
            lastError = workspaceError(for: FileStoreError.fileChangedDuringRead)
            return .handled
        }
        // The write failed only because the on-disk baseline had moved, not
        // because its content actually diverged (a real divergence lands in
        // `.conflict` above). Reconciliation just brought the baseline
        // current, so retry the save the user actually asked for instead of
        // leaving it dirty with no error and no indication anything failed —
        // but only once: a second consecutive metadata-only change means
        // something external is outpacing us, and that deserves a real error
        // rather than another silent attempt. Preserve the caller's
        // destination policy across that retry.
        return await saveAttempt(
            isRetry: true,
            destinationPolicy: retry.destinationPolicy,
            encodingOverride: retry.encodingOverride,
            target: reconciliation.document,
            continuingOperation: retry.operation
        )
    }

    private func readConflictSnapshot(_ document: FileDocument, at url: URL) async -> Result<FileSnapshot, Error> {
        let afterRead = afterSaveConflictRead
        return await Task.detached(priority: .userInitiated) {
            defer { afterRead?() }
            return Result { try document.fileStore.readSnapshot(from: url, decoding: document.encoding.decodingPolicy) }
        }.value
    }

    /// Baseline-compatible admission permits ordinary local edits while the read is suspended. It does not
    /// claim to distinguish external histories that return to identical values; publication remains conditional.
    private func hasSameConflictReadBaseline(_ lhs: FileDocument, _ rhs: FileDocument) -> Bool {
        lhs.lastKnownRevision == rhs.lastKnownRevision && lhs.restoredBaseSHA256 == rhs.restoredBaseSHA256
            && lhs.pendingExternalRevision == rhs.pendingExternalRevision && lhs.backingState == rhs.backingState
            && lhs.encoding == rhs.encoding
    }
}
