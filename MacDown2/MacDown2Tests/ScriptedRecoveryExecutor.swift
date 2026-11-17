import FileCore
import Foundation
@testable import MacDown2

/// A scripted `RecoveryActionExecuting` fake for `ExternalFileControllerRecoveryTests`.
/// Split into its own file — it's a standalone fake with no dependency on the
/// struct it supports — to stay under the file-length lint budget.
actor ScriptedRecoveryExecutor: RecoveryActionExecuting {
    private struct PersistFailureTarget {
        let id: String
        let epoch: UUID
        let afterVersion: UInt
    }

    private var failures: Set<ExternalFileController.RecoveryRetryKind> = []
    private var targetedPersistFailure: PersistFailureTarget?
    private(set) var calls: [ExternalFileController.RecoveryRetryKind] = []

    func failNext(_ kind: ExternalFileController.RecoveryRetryKind) {
        failures.insert(kind)
    }

    func failNextPersist(for id: String, epoch: UUID, afterVersion: UInt) {
        targetedPersistFailure = PersistFailureTarget(id: id, epoch: epoch, afterVersion: afterVersion)
    }

    func persist(_ document: FileDocument) async -> Bool {
        calls.append(.persist)
        if let targetedPersistFailure,
           document.id == targetedPersistFailure.id,
           document.recoveryEpoch == targetedPersistFailure.epoch,
           document.mutationGeneration > targetedPersistFailure.afterVersion {
            self.targetedPersistFailure = nil
            return false
        }
        guard failures.remove(.persist) == nil else { return false }
        return await document.persistRecovery()
    }

    /// `remove` and `migrate` stay fully scripted (no real buffer IO): the
    /// shared `ExternalFileControllerRecoveryTests.retryRetainsAndClears...`
    /// coverage deliberately replays persist/remove/migrate for the same
    /// document value (same identity, epoch, and mutation generation) to
    /// exercise the controller's own retry bookkeeping in isolation. Routing
    /// these two through the real buffer would make the second call collide
    /// with the durable version fence the first call already recorded,
    /// failing for reasons that have nothing to do with what that test
    /// verifies. `persist` and `retire` (below) are the two actions other
    /// tests in this file assert against the real on-disk buffer, so those
    /// stay real.
    func remove(
        _: RecoveryBuffer,
        id: String,
        version _: UInt,
        epoch _: UUID
    ) -> RecoveryCleanupResult {
        calls.append(.remove)
        if failures.remove(.remove) != nil {
            return .failed(.removalFailed(URL(fileURLWithPath: id), 13))
        }
        return .removed
    }

    func migrate(
        _: RecoveryBuffer,
        oldID: String,
        sourceEpoch _: UUID,
        document _: FileDocument
    ) -> RecoveryMigrationOutcome {
        calls.append(.migrate)
        if failures.remove(.migrate) != nil {
            return .failed(.removalFailed(URL(fileURLWithPath: oldID), 13))
        }
        return .migrated
    }

    func retire(_ buffer: RecoveryBuffer, id: String, epoch: UUID) async -> RecoveryCleanupResult {
        calls.append(.retire)
        guard failures.remove(.retire) == nil else {
            return .failed(.removalFailed(URL(fileURLWithPath: id), 13))
        }
        return await buffer.retireWithOutcome(for: id, epoch: epoch)
    }
}
