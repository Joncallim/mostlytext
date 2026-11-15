import FileCore
import Foundation

/// The recovery executor is injectable only at the controller boundary. It
/// keeps retry-state coverage deterministic while production continues to use
/// the document's real recovery buffer.
protocol RecoveryActionExecuting: Sendable {
    func persist(_ document: FileDocument) async -> Bool
    func remove(
        _ buffer: RecoveryBuffer,
        id: String,
        version: UInt,
        epoch: UUID
    ) async -> RecoveryCleanupResult
    func migrate(
        _ buffer: RecoveryBuffer,
        oldID: String,
        sourceEpoch: UUID,
        document: FileDocument
    ) async -> RecoveryMigrationOutcome
    func retire(
        _ buffer: RecoveryBuffer,
        id: String,
        epoch: UUID
    ) async -> RecoveryCleanupResult
}

struct DefaultRecoveryActionExecutor: RecoveryActionExecuting {
    func persist(_ document: FileDocument) async -> Bool {
        await document.persistRecovery()
    }

    func remove(
        _ buffer: RecoveryBuffer,
        id: String,
        version: UInt,
        epoch: UUID
    ) async -> RecoveryCleanupResult {
        await buffer.removeWithOutcome(for: id, version: version, epoch: epoch)
    }

    func migrate(
        _ buffer: RecoveryBuffer,
        oldID: String,
        sourceEpoch: UUID,
        document: FileDocument
    ) async -> RecoveryMigrationOutcome {
        await buffer.migrateWithOutcome(
            from: oldID,
            to: document.id,
            content: document.text,
            version: document.mutationGeneration,
            sourceEpoch: sourceEpoch,
            destinationEpoch: document.recoveryEpoch
        )
    }

    func retire(_ buffer: RecoveryBuffer, id: String, epoch: UUID) async -> RecoveryCleanupResult {
        await buffer.retireWithOutcome(for: id, epoch: epoch)
    }
}

extension ExternalFileController {
    enum RecoveryRetryKind: Equatable, Sendable {
        case persist
        case remove
        case migrate
        case retire
    }

    enum RecoveryAction: Sendable {
        case persist(FileDocument, UInt)
        case remove(RecoveryBuffer, String, UInt, UUID, UInt)
        case migrate(
            RecoveryBuffer,
            oldID: String,
            sourceEpoch: UUID,
            document: FileDocument,
            ownerID: String,
            ownerEpoch: UUID,
            UInt
        )
        case retire(RecoveryBuffer, String, UUID, UInt)
    }

    struct RecoveryActionContext {
        let action: RecoveryAction
        let id: String
        let epoch: UUID
        let generation: UInt
    }

    func updateMonitorRevision(from document: FileDocument) {
        guard let url = document.fileURL?.standardizedFileURL else { return }
        let lifecycleGeneration = lifecycleGeneration
        let revision = document.lastKnownRevision?.fileObjectID
        let decoding = document.encoding.decodingPolicy
        Task { @MainActor [weak self] in
            guard let self,
                  isBindingCurrent(generation: lifecycleGeneration, url: url)
            else { return }
            await monitor.updateBaseline(priorFileObjectID: revision, decoding: decoding, expectedURL: url)
        }
    }

    func persistRecovery(for document: FileDocument) {
        enqueueRecovery(.persist(document, lifecycleGeneration))
    }

    func removeRecovery(for document: FileDocument) {
        enqueueRecovery(
            .remove(
                document.recoveryBuffer,
                document.id,
                document.mutationGeneration,
                document.recoveryEpoch,
                lifecycleGeneration
            )
        )
    }

    func migrateRecovery(from oldID: String, sourceEpoch: UUID, to document: FileDocument) {
        enqueueRecovery(
            .migrate(
                document.recoveryBuffer,
                oldID: oldID,
                sourceEpoch: sourceEpoch,
                document: document,
                ownerID: document.id,
                ownerEpoch: document.recoveryEpoch,
                lifecycleGeneration
            )
        )
    }

    func enqueueRecovery(
        _ action: RecoveryAction,
        resumeMoveWhenComplete: Bool = false,
        resumeCloseWhenComplete: Bool = false
    ) {
        let previous = recoveryTail
        recoveryTail = Task { [weak self] in
            if let previous {
                _ = await previous.result
            }
            guard let self else { return }
            guard canExecuteRecoveryRetry(action, resumesPendingMove: resumeMoveWhenComplete) else {
                await abandonStaleMoveRetry(action)
                return
            }
            await performRecovery(action)
            if resumeMoveWhenComplete, recoveryRetryAction == nil {
                await resumePendingMove(after: action)
            }
            if resumeCloseWhenComplete, recoveryRetryAction == nil {
                await resumePendingClose(after: action)
            }
        }
    }

    /// A failed move migration captures the complete document state that made
    /// the source lifetime safe to retire. Replaying it after an edit would
    /// retire recovery for text the migration never persisted. Recheck on the
    /// serialized recovery lane, immediately before executing the retry.
    private func canExecuteRecoveryRetry(
        _ action: RecoveryAction,
        resumesPendingMove: Bool
    ) -> Bool {
        guard resumesPendingMove, case .migrate = action else { return true }
        guard let pendingMove else { return true }
        guard matchesPendingMoveRetry(action), let model else { return false }
        return isCurrent(pendingMove.context, in: model)
    }

    /// A stale move retry must not remain as a permanently inert button. The
    /// retained source recovery was never migrated, so preserve the current
    /// text and surface the normal unavailable/Save As path instead.
    private func abandonStaleMoveRetry(_ action: RecoveryAction) async {
        guard case .migrate = action, pendingMove != nil else { return }
        pendingMove = nil
        recoveryRetryAction = nil
        guard let model, let current = model.activeDocument else { return }
        let replacement = current.markingBackingUnavailable(.missingOrMoved)
        model.tabStore.updateActiveDocument { _ in replacement }
        latestExternalSnapshot = nil
        noticeTask?.cancel()
        notice = .unavailable(.missingOrMoved)
        if await recoveryExecutor.persist(replacement) {
            coordinator?.scheduleSaveSession()
        } else {
            let retry = RecoveryAction.persist(replacement, lifecycleGeneration)
            recoveryRetryAction = retry
            notice = await .recoveryCleanup(replacement.recoveryBuffer.recoveryLocation(
                for: replacement.id,
                epoch: replacement.recoveryEpoch
            ))
        }
    }

    private func performRecovery(_ action: RecoveryAction) async {
        switch action {
        case let .persist(document, generation):
            await performRecoveryPersist(document, generation: generation, action: action)
        case let .remove(buffer, id, version, epoch, generation):
            let context = RecoveryActionContext(action: action, id: id, epoch: epoch, generation: generation)
            _ = await performRecoveryRemoval(
                buffer,
                version: version,
                context: context
            )
        case let .migrate(buffer, oldID, sourceEpoch, document, ownerID, ownerEpoch, generation):
            let context = RecoveryActionContext(
                action: action,
                id: ownerID,
                epoch: ownerEpoch,
                generation: generation
            )
            _ = await performRecoveryMigration(
                buffer,
                oldID: oldID,
                sourceEpoch: sourceEpoch,
                document: document,
                context: context
            )
        case let .retire(buffer, id, epoch, generation):
            let context = RecoveryActionContext(action: action, id: id, epoch: epoch, generation: generation)
            _ = await performRecoveryRetirement(buffer, context: context)
        }
    }

    private func performRecoveryPersist(
        _ document: FileDocument,
        generation: UInt,
        action: RecoveryAction
    ) async {
        guard await recoveryExecutor.persist(document) else {
            guard isRetainedRecoveryPersist(document, generation: generation)
            else { return }
            recoveryRetryAction = action
            let location = await document.recoveryBuffer.recoveryLocation(
                for: document.id,
                epoch: document.recoveryEpoch
            )
            notice = .recoveryCleanup(location)
            return
        }
        if matchesRecoveryPersistRetry(document, generation: generation),
           isRetainedRecoveryPersist(document, generation: generation) {
            recoveryRetryAction = nil
            if case .recoveryCleanup = notice {
                notice = .none
            }
        }
    }

    func performRecoveryRemoval(
        _ buffer: RecoveryBuffer,
        version: UInt,
        context: RecoveryActionContext
    ) async -> RecoveryCleanupResult {
        let outcome = await recoveryExecutor.remove(
            buffer,
            id: context.id,
            version: version,
            epoch: context.epoch
        )
        guard isCurrentRecoveryAction(id: context.id, epoch: context.epoch, generation: context.generation) else {
            return outcome
        }
        if outcome.isAbsent {
            clearRecoveryRetryIfCurrent(id: context.id, epoch: context.epoch, generation: context.generation)
        } else {
            recoveryRetryAction = context.action
            await surfaceRecoveryCleanup(outcome, buffer: buffer, id: context.id, epoch: context.epoch)
        }
        return outcome
    }

    func performRecoveryMigration(
        _ buffer: RecoveryBuffer,
        oldID: String,
        sourceEpoch: UUID,
        document: FileDocument,
        context: RecoveryActionContext
    ) async -> RecoveryMigrationOutcome {
        let outcome = await recoveryExecutor.migrate(
            buffer,
            oldID: oldID,
            sourceEpoch: sourceEpoch,
            document: document
        )
        guard isCurrentRecoveryAction(
            id: context.id,
            epoch: context.epoch,
            generation: context.generation
        )
        else { return outcome }
        if outcome.isComplete {
            clearRecoveryRetryIfCurrent(id: context.id, epoch: context.epoch, generation: context.generation)
        } else {
            recoveryRetryAction = context.action
            let location = await buffer.recoveryLocation(for: oldID, epoch: sourceEpoch)
            notice = .recoveryCleanup(location)
        }
        return outcome
    }

    private func performRecoveryRetirement(
        _ buffer: RecoveryBuffer,
        context: RecoveryActionContext
    ) async -> RecoveryCleanupResult {
        let outcome = await recoveryExecutor.retire(buffer, id: context.id, epoch: context.epoch)
        guard isCurrentRecoveryAction(id: context.id, epoch: context.epoch, generation: context.generation) else {
            return outcome
        }
        if outcome.isAbsent {
            clearRecoveryRetryIfCurrent(id: context.id, epoch: context.epoch, generation: context.generation)
        } else {
            recoveryRetryAction = context.action
            await surfaceRecoveryCleanup(outcome, buffer: buffer, id: context.id, epoch: context.epoch)
        }
        return outcome
    }

    /// Drains the controller-owned persistence stream before retiring the
    /// exact document lifetime. This keeps native close from racing a queued
    /// conflict/unavailable recovery persist.
    func retireRecovery(
        for document: FileDocument,
        resumeCloseOnSuccess: Bool = false
    ) async -> RecoveryCleanupResult {
        await drainRecovery()
        let action = RecoveryAction.retire(
            document.recoveryBuffer,
            document.id,
            document.recoveryEpoch,
            lifecycleGeneration
        )
        let context = RecoveryActionContext(
            action: action,
            id: document.id,
            epoch: document.recoveryEpoch,
            generation: lifecycleGeneration
        )
        let outcome = await performRecoveryRetirement(document.recoveryBuffer, context: context)
        if outcome.isAbsent {
            pendingClose = nil
        } else if resumeCloseOnSuccess {
            pendingClose = PendingClose(document: document, lifecycleGeneration: lifecycleGeneration)
        }
        return outcome
    }

    func drainRecovery() async {
        if let recoveryTail {
            _ = await recoveryTail.result
        }
    }

    func showTransient(_ nextNotice: Notice) {
        noticeTask?.cancel()
        notice = nextNotice
        noticeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard let self, !disposed else { return }
            notice = .none
        }
    }

    func surfaceRecoveryCleanup(
        _ outcome: RecoveryCleanupResult,
        buffer: RecoveryBuffer,
        id: String,
        epoch: UUID
    ) async {
        guard !outcome.isAbsent else { return }
        noticeTask?.cancel()
        notice = await .recoveryCleanup(buffer.recoveryLocation(for: id, epoch: epoch))
    }

    private func isCurrentRecoveryAction(id: String, epoch: UUID, generation: UInt) -> Bool {
        guard !disposed,
              lifecycleGeneration == generation,
              let document = model?.activeDocument
        else { return false }
        return document.id == id && document.recoveryEpoch == epoch
    }

    private func clearRecoveryRetryIfCurrent(id: String, epoch: UUID, generation: UInt) {
        guard isCurrentRecoveryAction(id: id, epoch: epoch, generation: generation) else { return }
        recoveryRetryAction = nil
        if case .recoveryCleanup = notice {
            notice = .none
        }
    }
}
