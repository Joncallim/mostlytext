import Darwin
import Foundation

extension ExportManagedCompanions {
    func checkPublishedInventory(expectedDigest: Data?) throws {
        guard try record.inventoryPublished else { return }
        guard let directory, let inventory = try loadInventory(in: directory.descriptor),
              inventory.value.primaryDigest == expectedDigest,
              let previous = try record.previousInventory else { throw ExportError.unsafePublication }
        let actual = inventory.metadataReceipt.value.stamp
        try protection.admission.checkRecoveryObject(actual)
        if previous.stamp == actual {
            return
        }
        guard let next = try record.files.first(where: { $0.role == .inventory }), next.receipt != nil
        else { throw ExportError.unsafePublication }
        let receipt = try journal.receipt(named: next.temporary)
        _ = try receipt.inspectingRenamedFile(ExportCompanionInventoryRecord.fileName, in: directory.descriptor)
    }

    func publishInitialInventory(expectedDigest: Data?) throws {
        guard try !record.inventoryPublished else { return }
        try installInventory(expectedDigest: expectedDigest)
        guard let directory, let inventory = try loadInventory(in: directory.descriptor),
              inventory.value.primaryDigest == expectedDigest else { throw ExportError.unsafePublication }
        try update { next in
            next.inventoryPublished = true
            next.publishedOwnedCount = next.owned.count
            next.previousInventory = inventory.metadataReceipt.value
            next.files.removeAll { $0.role == .inventory }
        }
        try checkpoint("initial-inventory-recorded")
    }

    func installInventory(expectedDigest: Data?) throws {
        guard let directory else { throw ExportError.unsafePublication }
        try checkState(expectedDigest: expectedDigest)
        let file = try inventoryWorkFile()
        let receipt = try inventoryReceipt(file, expectedDigest: expectedDigest)
        let actual = try ExportCompanionFiles.stamp(file.name, in: directory.descriptor)
        if let actual, receipt.matchesMetadata(actual),
           try ExportReceiptInspection.verify(receipt, name: file.name, in: directory.descriptor, matching: actual) {
            // Restart after the swap: the new public inode already proves itself.
            try finishInventory(file, receipt: receipt, expectedDigest: expectedDigest)
            return
        }
        try promoteInventory(file, receipt: receipt, actual: actual, expectedDigest: expectedDigest)
        try finishInventory(file, receipt: receipt, expectedDigest: expectedDigest)
    }

    private func inventoryWorkFile() throws -> Record.WorkFile {
        let file: Record.WorkFile
        if let existing = try record.files.first(where: { $0.role == .inventory }) {
            file = existing
        } else {
            file = try .init(name: ExportCompanionInventoryRecord.fileName,
                             temporary: record.temporaryName(suffix: ".stage"),
                             role: .inventory, mimeType: nil, receipt: nil)
            try update { $0.files.append(file) }
            try checkpoint("inventory-intent-saved")
        }
        return file
    }

    private func inventoryReceipt(_ file: Record.WorkFile, expectedDigest: Data?) throws -> ExportOwnedFileReceipt {
        guard let directory else { throw ExportError.unsafePublication }
        let receipt: ExportOwnedFileReceipt
        if file.receipt != nil {
            receipt = try journal.receipt(named: file.temporary)
        } else {
            guard try ExportCompanionFiles.stamp(file.temporary, in: directory.descriptor) == nil
            else { throw Filesystem.recoveryRequired(directory: directory.descriptor, name: file.temporary) }
            let state = try record
            let known = state.phase == .committed ? state.desiredReferencesKnown : state.priorReferencesKnown
            let required = known ? (state.phase == .committed ? state.requiredNames : state.priorRequiredNames) : []
            receipt = try ExportCompanionFiles.create(file.temporary, in: directory.descriptor, bytes: { identity in
                try self.journal.authentication.seal(ExportCompanionInventoryRecord(
                    binding: state.binding, directory: Filesystem.directoryStamp(directory.descriptor),
                    metadata: identity, primaryDigest: expectedDigest,
                    referencesKnown: known, requiredNames: required, owned: state.owned
                ))
            }, afterCreation: { identity in
                try self.protection.admission.checkRecoveryObject(identity)
                try self.checkpoint("inventory-created")
            })
            try update { next in
                guard let index = next.files.firstIndex(where: { $0.temporary == file.temporary })
                else { throw ExportError.unsafePublication }
                next.files[index].receipt = ExportJournalRecord.Receipt(receipt)
            }
            try checkpoint("inventory-receipt-saved")
        }
        return receipt
    }

    private func promoteInventory(_ file: Record.WorkFile, receipt: ExportOwnedFileReceipt,
                                  actual: Filesystem.Stamp?, expectedDigest: Data?) throws {
        guard let directory else { throw ExportError.unsafePublication }
        let staged = try receipt.inspectingRenamedFile(file.temporary, in: directory.descriptor)
        try checkState(expectedDigest: expectedDigest)
        if try record.previousInventory != nil {
            let previous = try journal.receipt(named: ExportCompanionInventoryRecord.fileName)
            guard let actual, previous.matchesMetadata(actual),
                  try ExportReceiptInspection.verify(previous, name: file.name,
                                                     in: directory.descriptor, matching: actual)
            else { throw Filesystem.recoveryRequired(directory: directory.descriptor, name: file.temporary) }
            // The displaced old metadata name and its quarantine are durable
            // before the exchange. It is not retired until the swap is verified.
            try queueRetirement(file.temporary, receipt: previous)
            try exchangeInventory(file, staged: staged, previous: previous, actual: actual)
        } else {
            guard actual == nil else { throw ExportError.unsafePublication }
            try protection.withCutoff(staged.stamp) {
                guard try Filesystem.childStamp(file.temporary, in: directory.descriptor) == staged.stamp,
                      renameatx_np(directory.descriptor, file.temporary, directory.descriptor,
                                   file.name, UInt32(RENAME_EXCL)) == 0
                else { throw ExportError.unsafePublication }
            }
            guard fsync(directory.descriptor) == 0 else { throw Filesystem.posixFailure() }
            try checkpoint("inventory-installed")
        }
    }

    private func exchangeInventory(_ file: Record.WorkFile, staged: ExportOwnedFileReceipt,
                                   previous: ExportOwnedFileReceipt, actual: Filesystem.Stamp) throws {
        guard let directory else { throw ExportError.unsafePublication }
        try protection.admission.checkRecoveryObject(staged.stamp)
        try protection.withCutoff(previous.stamp) {
            guard try Filesystem.childStamp(file.name, in: directory.descriptor) == actual,
                  try Filesystem.childStamp(file.temporary, in: directory.descriptor) == staged.stamp,
                  renameatx_np(directory.descriptor, file.temporary, directory.descriptor,
                               file.name, UInt32(RENAME_SWAP)) == 0
            else { throw ExportError.unsafePublication }
        }
        guard fsync(directory.descriptor) == 0 else { throw Filesystem.posixFailure() }
        try checkpoint("inventory-swapped")
        do { _ = try previous.inspectingRenamedFile(file.temporary, in: directory.descriptor) } catch {
            try restoreExchange(file, installed: staged)
            throw Filesystem.recoveryRequired(directory: directory.descriptor, name: file.temporary)
        }
    }

    private func finishInventory(_ file: Record.WorkFile, receipt: ExportOwnedFileReceipt,
                                 expectedDigest: Data?) throws {
        guard let directory, let inventory = try loadInventory(in: directory.descriptor),
              inventory.value.primaryDigest == expectedDigest,
              receipt.matchesMetadata(inventory.metadataReceipt.value.stamp)
        else { throw ExportError.unsafePublication }
        _ = try receipt.inspectingRenamedFile(file.name, in: directory.descriptor)
        try checkState(expectedDigest: expectedDigest)
        try drainRetirements(expectedDigest: expectedDigest, includeMetadata: true)
        try checkpoint("inventory-finalized")
    }

    private func restoreExchange(_ file: Record.WorkFile, installed: ExportOwnedFileReceipt) throws {
        guard let directory else { throw ExportError.unsafePublication }
        let current = try installed.inspectingRenamedFile(file.name, in: directory.descriptor)
        let displaced = try Filesystem.childStamp(file.temporary, in: directory.descriptor)
        try protection.admission.checkRecoveryObject(current.stamp)
        try protection.withCutoff(displaced) {
            guard try Filesystem.childStamp(file.name, in: directory.descriptor) == current.stamp,
                  try Filesystem.childStamp(file.temporary, in: directory.descriptor) == displaced,
                  renameatx_np(directory.descriptor, file.temporary, directory.descriptor,
                               file.name, UInt32(RENAME_SWAP)) == 0
            else { throw Filesystem.recoveryRequired(directory: directory.descriptor, name: file.temporary) }
        }
        guard fsync(directory.descriptor) == 0 else { throw Filesystem.posixFailure() }
    }
}
