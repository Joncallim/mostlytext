import CryptoKit
import Darwin
import Foundation

extension ExportManagedCompanions {
    func recover() throws {
        guard journal.pending != nil else { return }
        let state = try record
        let observed = try ExportPrimaryRecovery.digest(of: input.url.lastPathComponent, in: parent.descriptor)
        guard observed == state.priorDigest || observed == state.desiredDigest,
              state.phase != .committed || observed == state.desiredDigest,
              state.phase != .aborted || observed == state.priorDigest
        else { throw ExportError.unsafePublication }
        guard state.directory != nil else {
            guard try ExportCompanionFiles.stamp(input.assetsDirectoryName, in: parent.descriptor) == nil
            else { throw Filesystem.recoveryRequired(directory: parent.descriptor, name: input.assetsDirectoryName) }
            try journal.finish()
            return
        }
        directory = try openDirectory()
        guard directory != nil else { throw ExportError.unsafePublication }
        try checkState(expectedDigest: observed)
        if state.phase == .preparing {
            let committed = observed == state.desiredDigest && observed != state.priorDigest
            try update { $0.phase = committed ? .committed : .aborted }
            try checkpoint(committed ? "commit-recorded" : "abort-recorded")
        }
        try complete(expectedDigest: observed)
    }

    func finish() throws {
        guard journal.pending != nil else { return }
        let desired = try record.desiredDigest
        try checkState(expectedDigest: desired)
        try update { $0.phase = .committed }
        try checkpoint("commit-recorded")
        try complete(expectedDigest: desired)
    }

    private func complete(expectedDigest: Data?) throws {
        try reconcileWorkFiles(expectedDigest: expectedDigest)
        let state = try record
        if state.phase == .committed {
            try verifyRequiredResources()
        }
        try drainRetirements(expectedDigest: expectedDigest, includeMetadata: false)
        try retireObsoleteResources(expectedDigest: expectedDigest)
        try installInventory(expectedDigest: expectedDigest)
        try checkState(expectedDigest: expectedDigest)
        try journal.finish()
        try checkpoint("companion-finished")
        directory = nil
    }

    private func reconcileWorkFiles(expectedDigest: Data?) throws {
        guard let directory else { throw ExportError.unsafePublication }
        if try record.createdDirectory,
           try ExportCompanionFiles.stamp(ExportFileWriter.markerFileName, in: directory.descriptor) == nil,
           try !record.files.contains(where: { $0.role == .marker }) {
            let temporary = try record.temporaryName(suffix: ".stage")
            try update { $0.files.append(.init(name: ExportFileWriter.markerFileName, temporary: temporary,
                                               role: .marker, mimeType: nil, receipt: nil)) }
        }
        for file in try record.files where file.role != .inventory {
            try reconcileFile(file, expectedDigest: expectedDigest)
        }
        try verifyMarker(in: directory.descriptor)
    }

    private func reconcileFile(_ file: Record.WorkFile, expectedDigest: Data?) throws {
        guard let directory else { throw ExportError.unsafePublication }
        let staged = try ExportCompanionFiles.stamp(file.temporary, in: directory.descriptor)
        let final = try ExportCompanionFiles.stamp(file.name, in: directory.descriptor)
        guard file.receipt != nil else {
            guard staged == nil else {
                throw Filesystem.recoveryRequired(directory: directory.descriptor, name: file.temporary)
            }
            if file.role == .marker, final == nil {
                try recreateMarker(file, expectedDigest: expectedDigest)
            }
            return
        }
        let receipt = try journal.receipt(named: file.temporary)
        if let staged, try !reconcileStage(file, receipt: receipt, staged: staged,
                                           final: final, expectedDigest: expectedDigest) {
            return
        }
        guard let actual = try ExportCompanionFiles.stamp(file.name, in: directory.descriptor),
              receipt.matchesMetadata(actual),
              try ExportReceiptInspection.verify(receipt, name: file.name,
                                                 in: directory.descriptor, matching: actual)
        else {
            try update { $0.owned.removeAll { $0.name == file.name } }
            return // Foreign/modified final objects remain untouched.
        }
        let installed = try receipt.inspectingRenamedFile(file.name, in: directory.descriptor)
        try update { next in
            if file.role == .resource, let mimeType = file.mimeType,
               !next.owned.contains(where: { $0.name == file.name }) {
                next.owned.append(.init(name: file.name, mimeType: mimeType,
                                        receipt: ExportJournalRecord.Receipt(installed)))
            }
        }
    }

    private func reconcileStage(_ file: Record.WorkFile, receipt: ExportOwnedFileReceipt,
                                staged: Filesystem.Stamp, final: Filesystem.Stamp?,
                                expectedDigest: Data?) throws -> Bool {
        guard let directory else { throw ExportError.unsafePublication }
        guard receipt.matchesMetadata(staged),
              try ExportReceiptInspection.verify(receipt, name: file.temporary,
                                                 in: directory.descriptor, matching: staged)
        else { throw Filesystem.recoveryRequired(directory: directory.descriptor, name: file.temporary) }
        if file.role == .marker, final == nil {
            try checkState(expectedDigest: expectedDigest)
            try protection.withCutoff(receipt.stamp) {
                guard try Filesystem.childStamp(file.temporary, in: directory.descriptor) == staged,
                      renameatx_np(directory.descriptor, file.temporary, directory.descriptor,
                                   file.name, UInt32(RENAME_EXCL)) == 0
                else { throw ExportError.unsafePublication }
            }
            guard fsync(directory.descriptor) == 0 else { throw Filesystem.posixFailure() }
        } else {
            try queueRetirement(file.temporary, receipt: receipt)
            return false
        }
        return true
    }

    private func recreateMarker(_ file: Record.WorkFile, expectedDigest: Data?) throws {
        guard let directory else { throw ExportError.unsafePublication }
        let bytes = try ExportAssetOwnerMarker.bytes(primary: input.url.lastPathComponent,
                                                     assets: input.assetsDirectoryName)
        try checkState(expectedDigest: expectedDigest)
        let receipt = try ExportCompanionFiles.create(file.temporary, in: directory.descriptor, bytes: { _ in bytes },
                                                      afterCreation: { identity in
                                                          try self.protection.admission.checkRecoveryObject(identity)
                                                      })
        try update { next in
            guard let index = next.files.firstIndex(where: { $0.temporary == file.temporary })
            else { throw ExportError.unsafePublication }
            next.files[index].receipt = ExportJournalRecord.Receipt(receipt)
        }
        // Replay once with the newly persisted receipt; no recursive file creation.
        try reconcileWorkFiles(expectedDigest: expectedDigest)
    }

    func verifyRequiredResources() throws {
        guard let directory else { throw ExportError.unsafePublication }
        var aggregate = 0
        for name in try record.requiredNames {
            guard let bytes = try Filesystem.readBoundedFile(
                name, in: directory.descriptor, maxBytes: ExportResourceBudget.standard.maxSingleResourceBytes
            ), aggregate <= ExportResourceBudget.standard.maxAggregateResourceBytes - bytes.count,
            name.hasPrefix(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() + ".")
            else { throw ExportError.unsafePublication }
            aggregate += bytes.count
        }
    }

    private func retireObsoleteResources(expectedDigest: Data?) throws {
        guard let directory else { throw ExportError.unsafePublication }
        let state = try record
        let eligible: Set<String>
        if state.phase == .committed {
            guard state.desiredReferencesKnown, state.retireObsoleteResources else { return }
            eligible = Set(state.owned.map(\.name)).subtracting(state.requiredNames)
        } else {
            guard state.phase == .aborted, state.priorReferencesKnown else { return }
            eligible = Set(state.files.filter { $0.role == .resource }.map(\.name))
                .subtracting(state.priorRequiredNames)
        }
        for entry in state.owned where eligible.contains(entry.name) {
            let receipt = try journal.receipt(named: entry.name)
            guard let actual = try ExportCompanionFiles.stamp(entry.name, in: directory.descriptor),
                  receipt.matchesMetadata(actual),
                  (try? protection.admission.checkRecoveryObject(actual)) != nil,
                  (try? ExportReceiptInspection.verify(receipt, name: entry.name,
                                                       in: directory.descriptor, matching: actual)) == true
            else {
                try update { $0.owned.removeAll { $0.name == entry.name } }
                continue
            }
            try queueRetirement(entry.name, receipt: receipt)
            try drainRetirements(expectedDigest: expectedDigest, includeMetadata: false)
        }
    }

    func queueRetirement(_ name: String, receipt: ExportOwnedFileReceipt) throws {
        guard try !record.retirements.contains(where: { $0.name == name }) else { return }
        let quarantine = try record.temporaryName(suffix: ".retired")
        try update { $0.retirements.append(.init(name: name, quarantine: quarantine,
                                                 receipt: ExportJournalRecord.Receipt(receipt))) }
        try checkpoint("retirement-intent-saved")
    }

    func drainRetirements(expectedDigest: Data?, includeMetadata: Bool) throws {
        guard let directory else { throw ExportError.unsafePublication }
        let metadataName = try record.files.first(where: { $0.role == .inventory })?.temporary
        for item in try record.retirements where includeMetadata || item.name != metadataName {
            try ExportCompanionMutation(owner: self, expectedDigest: expectedDigest).retire(item)
            try update { next in
                next.retirements.removeAll { $0.quarantine == item.quarantine }
                next.owned.removeAll { $0.name == item.name }
                next.files.removeAll {
                    $0.role != .inventory && ($0.temporary == item.name || $0.name == item.name)
                }
            }
        }
    }
}
