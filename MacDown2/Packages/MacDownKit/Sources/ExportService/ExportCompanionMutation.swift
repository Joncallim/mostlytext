import Darwin
import Foundation

/// Recorded quarantine moves are replayable on either side of rename/unlink.
/// The caller rechecks primary, directory and producer authority at each move.
struct ExportCompanionMutation {
    let owner: ExportManagedCompanions
    let expectedDigest: Data?
    private typealias Filesystem = ExportPublicationFilesystem

    func retire(_ item: ExportCompanionPendingRecord.Retirement) throws {
        guard let directory = owner.directory?.descriptor else { throw ExportError.unsafePublication }
        let journal = owner.journal
        let protection = owner.protection
        let receipt = try journal.receipt(named: item.quarantine)
        try protection.admission.checkRecoveryObject(receipt.stamp)
        try owner.checkState(expectedDigest: expectedDigest)
        guard try moveToQuarantine(item, receipt: receipt, directory: directory) else { return }
        do {
            let current = try Filesystem.childStamp(item.quarantine, in: directory)
            guard receipt.matchesMetadata(current),
                  try ExportReceiptInspection.verify(receipt, name: item.quarantine,
                                                     in: directory, matching: current)
            else { throw ExportError.unsafePublication }
            try owner.checkState(expectedDigest: expectedDigest)
            try protection.withCutoff(receipt.stamp) {
                guard try Filesystem.childStamp(item.quarantine, in: directory) == current
                else { throw ExportError.unsafePublication }
                guard unlinkat(directory, item.quarantine, 0) == 0 else { throw Filesystem.posixFailure() }
            }
            guard fsync(directory) == 0 else { throw Filesystem.posixFailure() }
        } catch {
            // Never overwrite a competing original while restoring a changed
            // quarantine. A collision retains both names with a precise error.
            try ExportFileRetirement.restoreQuarantine(item.quarantine, as: item.name, in: directory,
                                                       protection: protection)
            throw error
        }
        try owner.checkpoint("retirement-unlinked")
    }

    private func moveToQuarantine(_ item: ExportCompanionPendingRecord.Retirement,
                                  receipt: ExportOwnedFileReceipt, directory: Int32) throws -> Bool {
        let protection = owner.protection
        let original = try Filesystem.primaryBaseline(item.name, in: directory)
        if let current = try Filesystem.primaryBaseline(item.quarantine, in: directory) {
            guard original == nil, receipt.matchesMetadata(current),
                  try ExportReceiptInspection.verify(receipt, name: item.quarantine,
                                                     in: directory, matching: current)
            else { throw Filesystem.recoveryRequired(directory: directory, name: item.quarantine) }
        } else if let original {
            guard receipt.matchesMetadata(original),
                  try ExportReceiptInspection.verify(receipt, name: item.name, in: directory, matching: original)
            else { throw Filesystem.recoveryRequired(directory: directory, name: item.name) }
            try owner.checkState(expectedDigest: expectedDigest)
            try protection.withCutoff(receipt.stamp) {
                guard try Filesystem.childStamp(item.name, in: directory) == original
                else { throw ExportError.unsafePublication }
                guard renameatx_np(directory, item.name, directory, item.quarantine, UInt32(RENAME_EXCL)) == 0
                else { throw Filesystem.posixFailure() }
            }
            guard fsync(directory) == 0 else { throw Filesystem.posixFailure() }
            try owner.checkpoint("retirement-renamed")
        } else {
            return false // A previous replay already unlinked this exact recorded item.
        }
        return true
    }
}
