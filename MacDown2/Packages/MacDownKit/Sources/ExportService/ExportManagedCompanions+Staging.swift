import Darwin
import Foundation

extension ExportManagedCompanions {
    func stageResources() throws {
        guard let directory else { throw ExportError.unsafePublication }
        let metadata = try record.previousInventory.map { _ in try loadInventory(in: directory.descriptor) }
        let metadataReceipt = try metadata.flatMap(\.self).map {
            try ExportOwnedFileReceipt(authenticatedCompanion: $0.metadataReceipt)
        }
        var retained = try ExportPublicationRetention.scanAssets(
            directory.descriptor, limits: hooks.retentionLimit, authenticatedInventory: metadataReceipt
        )
        var seen = Set<String>()
        for resource in input.resources where seen.insert(resource.identity.fileName).inserted {
            try Task.checkCancellation()
            try protection.lease.checkActive()
            let name = resource.identity.fileName
            try retained.reserve(name: name, bytes: resource.bytes.count, limits: hooks.retentionLimit)
            _ = try install(resource.bytes, named: name, role: .resource, mimeType: resource.identity.mimeType)
        }
    }

    @discardableResult
    func install(_ bytes: Data, named name: String, role: Record.FileRole, mimeType: String?) throws
        -> Filesystem.Stamp {
        guard let directory else { throw ExportError.unsafePublication }
        try checkState(expectedDigest: record.priorDigest)
        if let existing = try Filesystem.existingBytes(bytes, named: name, in: directory.descriptor) {
            // Matching bytes permit reuse only. They never manufacture ownership.
            return existing
        }
        let temporary = try record.temporaryName(suffix: ".stage")
        try update { $0.files.append(.init(name: name, temporary: temporary, role: role,
                                           mimeType: mimeType, receipt: nil)) }
        try checkpoint("stage-intent-saved")
        try checkState(expectedDigest: record.priorDigest)
        let receipt = try ExportCompanionFiles.create(temporary, in: directory.descriptor, bytes: { _ in bytes },
                                                      afterCreation: { identity in
                                                          try self.protection.admission.checkRecoveryObject(identity)
                                                          try self.checkpoint("stage-created")
                                                      })
        try update { next in
            guard let index = next.files.firstIndex(where: { $0.temporary == temporary })
            else { throw ExportError.unsafePublication }
            next.files[index].receipt = ExportJournalRecord.Receipt(receipt)
        }
        try checkpoint("stage-receipt-saved")
        try checkState(expectedDigest: record.priorDigest)
        try protection.withCutoff(receipt.stamp) {
            guard try Filesystem.childStamp(temporary, in: directory.descriptor) == receipt.stamp
            else { throw ExportError.unsafePublication }
            guard renameatx_np(directory.descriptor, temporary, directory.descriptor, name, UInt32(RENAME_EXCL)) == 0
            else { throw Filesystem.posixFailure() }
        }
        guard fsync(directory.descriptor) == 0 else { throw Filesystem.posixFailure() }
        try checkpoint("stage-renamed")
        let installed = try receipt.inspectingRenamedFile(name, in: directory.descriptor)
        try update { next in
            if role == .resource, let mimeType {
                next.owned.append(.init(name: name, mimeType: mimeType,
                                        receipt: ExportJournalRecord.Receipt(installed)))
            }
            guard let index = next.files.firstIndex(where: { $0.temporary == temporary })
            else { throw ExportError.unsafePublication }
            next.files[index].receipt = ExportJournalRecord.Receipt(installed)
        }
        try checkpoint("stage-installation-saved")
        return installed.stamp
    }

    func currentStage(includeResources: Bool) throws -> Stage {
        guard let directory else { throw ExportError.unsafePublication }
        let stamp = try Filesystem.directoryStamp(directory.descriptor)
        var names = [ExportFileWriter.markerFileName]
        if includeResources {
            names += try record.requiredNames
        }
        if try record.previousInventory != nil {
            names.append(ExportCompanionInventoryRecord.fileName)
        }
        let entries = try names.map { try (name: $0, stamp: Filesystem.childStamp($0, in: directory.descriptor)) }
        let base = input.url.deletingLastPathComponent().appendingPathComponent(input.assetsDirectoryName,
                                                                                isDirectory: true)
        return Stage(directory: directory, stamp: stamp, entries: entries,
                     urls: names.filter { $0 != ExportCompanionInventoryRecord.fileName }
                         .map { base.appendingPathComponent($0) })
    }
}
