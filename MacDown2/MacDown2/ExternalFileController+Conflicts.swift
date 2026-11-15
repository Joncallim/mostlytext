import FileCore
import Foundation
import Workspace

extension ExternalFileController {
    func resolveConflict(_ resolution: ConflictResolution) async {
        guard !disposed,
              let model,
              let document = model.activeDocument,
              document.state == .conflict
        else { return }
        guard resolution != .cancel else {
            notice = .conflict
            return
        }

        let context = OperationContext(document: document, generation: lifecycleGeneration)
        let observation: DocumentFileObservation = if resolution == .keepMine, let latestExternalSnapshot {
            .available(latestExternalSnapshot)
        } else {
            await monitor.snapshotNow()
        }
        await afterConflictSnapshot?(observation)
        // Revalidate source authority and exact text while allowing a metadata-only generation change.
        // The earlier generation-only guard dropped a valid choice and left "Use Disk Version and Close" open.
        guard let current = model.activeDocument, isSameContent(context, as: current) else { return }

        await applyConflictObservation(observation, resolution: resolution, document: current, model: model)
    }

    /// `isCurrent(_:in:)` without the `mutationGeneration` comparison: the same document lifetime,
    /// URL, exact text, state, encoding and disk revisions the conflict choice was made against.
    private func isSameContent(_ context: OperationContext, as document: FileDocument) -> Bool {
        lifecycleGeneration == context.generation
            && document.id == context.documentID
            && document.fileURL?.standardizedFileURL == context.fileURL
            && document.text.isExactlyEqual(to: context.text)
            && document.state == context.state
            && document.pendingExternalRevision == context.pendingRevision
            && document.recoveryEpoch == context.recoveryEpoch
            && document.lastKnownRevision == context.lastKnownRevision
            && document.backingState == context.backingState
            && document.encoding == context.encoding
    }

    private func isSameUseExternalChoice(
        _ document: FileDocument, as current: FileDocument, generation: UInt, removedVersion: UInt
    ) -> Bool {
        !disposed && lifecycleGeneration == generation
            && current.id == document.id
            && current.fileURL?.standardizedFileURL == document.fileURL?.standardizedFileURL
            && current.recoveryEpoch == document.recoveryEpoch
            && current.mutationGeneration <= removedVersion
            && current.text.isExactlyEqual(to: document.text)
            && current.state == document.state
            && current.lastKnownRevision == document.lastKnownRevision
            && current.pendingExternalRevision == document.pendingExternalRevision
            && current.backingState == document.backingState
            && current.encoding == document.encoding
    }

    private func restoreRecoveryAfterSupersededChoice(
        tabID: UUID?, document: FileDocument, removedVersion: UInt, model: WorkspaceModel
    ) {
        guard let tabID,
              let durable = model.tabStore.advancingRecoveryVersion(
                  inTab: tabID, documentID: document.id, epoch: document.recoveryEpoch, after: removedVersion
              )
        else { return }
        persistRecovery(for: durable)
        coordinator?.scheduleSaveSession()
    }

    private func applyConflictObservation(
        _ observation: DocumentFileObservation,
        resolution: ConflictResolution,
        document: FileDocument,
        model: WorkspaceModel
    ) async {
        switch observation {
        case let .available(snapshot):
            await applyConflictResolution(resolution, snapshot: snapshot, document: document, model: model)
        case let .moved(snapshot):
            await applyMove(snapshot, to: document, model: model)
            guard let rebound = model.activeDocument,
                  rebound.fileURL?.standardizedFileURL == snapshot.revision.url.standardizedFileURL,
                  rebound.state == .conflict
            else { return }
            await applyConflictResolution(resolution, snapshot: snapshot, document: rebound, model: model)
        case let .missing(url):
            guard url.standardizedFileURL == boundURL else { return }
            applyUnavailable(.missingOrMoved, to: document, model: model)
        case let .unavailable(url, issue):
            guard url.standardizedFileURL == boundURL else { return }
            applyUnavailable(issue, to: document, model: model)
        }
    }

    /// What `applyConflictResolution` actually did. Reopen-with-Encoding used to infer success from the document's
    /// disk revision, which an unchanged document can already carry when the recovery cleanup failed.
    enum ConflictApplication: Equatable {
        case applied
        /// The user's document changed (edit, tab switch, Save As, disposal) while recovery cleanup was awaited, so
        /// the captured disk snapshot was NOT installed over it.
        case superseded
        case cleanupBlocked
        case notApplicable
    }

    @discardableResult
    func applyConflictResolution(
        _ resolution: ConflictResolution,
        snapshot: FileSnapshot,
        document: FileDocument,
        model: WorkspaceModel
    ) async -> ConflictApplication {
        switch resolution {
        case .keepMine:
            let replacement = document.keepingLocalChanges(acknowledging: snapshot.revision)
            model.tabStore.updateActiveDocument { _ in replacement }
            latestExternalSnapshot = nil
            persistRecovery(for: replacement)
            notice = .none
            synchronize(with: replacement)
            coordinator?.scheduleSaveSession()
            return .applied
        case .useExternal:
            let replacement = document.reloadedFromExternal(snapshot)
            let generation = lifecycleGeneration
            let tabID = model.tabStore.activeTab?.id
            let cleanup = await replacement.recoveryBuffer.removeForExternalReload(
                for: replacement.id,
                version: replacement.mutationGeneration,
                epoch: replacement.recoveryEpoch
            )
            await afterUseExternalRecoveryCleanup?()
            // The monitor may advance the pending disk revision while text and conflict state stay unchanged.
            // Admit the captured choice only against the same document, binding and disk authority. Do not use
            // mutationGeneration alone: metadata-only reconciles can advance it without superseding the choice.
            guard let current = model.activeDocument,
                  isSameUseExternalChoice(
                      document, as: current, generation: generation, removedVersion: replacement.mutationGeneration
                  )
            else {
                // The removal above may have erased the live draft's recovery at the same mutation version.
                // Advance that lifetime above the removal fence before queueing the exact current text again.
                restoreRecoveryAfterSupersededChoice(
                    tabID: tabID, document: document, removedVersion: replacement.mutationGeneration, model: model
                )
                return .superseded
            }
            guard cleanup.isAbsent else {
                await surfaceRecoveryCleanup(
                    cleanup,
                    buffer: replacement.recoveryBuffer,
                    id: replacement.id,
                    epoch: replacement.recoveryEpoch
                )
                return .cleanupBlocked
            }
            model.tabStore.updateActiveDocument { _ in replacement }
            replaceEditorText(with: replacement.text)
            latestExternalSnapshot = nil
            notice = .none
            synchronize(with: replacement)
            coordinator?.scheduleSaveSession()
            return .applied
        case .cancel:
            return .notApplicable
        }
    }
}
