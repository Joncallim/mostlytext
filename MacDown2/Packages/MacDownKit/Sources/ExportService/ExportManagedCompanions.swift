import CryptoKit
import Darwin
import Foundation

/// One producer-locked, parent-pinned companion transaction. The conservative
/// writer remains the path for callers without a private recovery location.
final class ExportManagedCompanions {
    typealias Filesystem = ExportPublicationFilesystem
    typealias Record = ExportCompanionPendingRecord
    typealias Entry = ExportCompanionInventoryRecord.Entry

    struct Stage {
        let directory: Filesystem.DirectoryHandle
        let stamp: Filesystem.Stamp
        let entries: [(name: String, stamp: Filesystem.Stamp)]
        let urls: [URL]
    }

    let input: HTMLFilePublicationInput
    let parent: Filesystem.DirectoryHandle
    let parentStamp: Filesystem.Stamp
    let journal: ExportCompanionJournal
    let protection: ExportRecoveryProtection
    let hooks: ExportPublicationHooks
    var directory: Filesystem.DirectoryHandle?

    init(input: HTMLFilePublicationInput, parent: Filesystem.DirectoryHandle, parentStamp: Filesystem.Stamp,
         producer: ExportJournalStore, protection: ExportRecoveryProtection, hooks: ExportPublicationHooks) throws {
        self.input = input
        self.parent = parent
        self.parentStamp = parentStamp
        journal = try ExportCompanionJournal(producer: producer)
        self.protection = protection
        self.hooks = hooks
    }

    var record: Record {
        get throws {
            guard let pending = journal.pending else { throw ExportError.unsafePublication }
            return pending.value
        }
    }

    func update(_ body: (inout Record) throws -> Void) throws {
        var next = try record
        try body(&next)
        try journal.save(next)
    }

    func checkpoint(_ name: String) throws {
        try hooks.companionCheckpoint?(name)
    }

    func checkState(expectedDigest: Data?) throws {
        try journal.checkCurrent()
        guard try Filesystem.directoryAtPath(input.url.deletingLastPathComponent().path, matches: parentStamp),
              try ExportCompanionObjectIdentity(parentStamp)
              .sameDirectory(as: Filesystem.directoryStamp(parent.descriptor)),
              try ExportPrimaryRecovery.digest(of: input.url.lastPathComponent, in: parent.descriptor) == expectedDigest
        else { throw ExportError.unsafePublication }
        if let directory {
            guard let identity = try record.directory,
                  try identity.sameDirectory(as: Filesystem.directoryStamp(directory.descriptor)),
                  try identity.sameDirectory(as: Filesystem.childStamp(input.assetsDirectoryName,
                                                                       in: parent.descriptor))
            else { throw ExportError.unsafePublication }
            if try ExportCompanionFiles.stamp(ExportFileWriter.markerFileName, in: directory.descriptor) != nil {
                try verifyMarker(in: directory.descriptor)
            } else {
                let state = try record
                guard state.createdDirectory, state.previousInventory == nil, state.owned.isEmpty,
                      state.files.allSatisfy({ $0.role == .marker }) else { throw ExportError.unsafePublication }
            }
        }
    }

    func openDirectory() throws -> Filesystem.DirectoryHandle? {
        let descriptor = openat(parent.descriptor, input.assetsDirectoryName,
                                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {
                return nil
            }
            throw ExportError.unsafePublication
        }
        let handle = Filesystem.DirectoryHandle(descriptor)
        let stamp = try Filesystem.directoryStamp(descriptor)
        guard try ExportCompanionObjectIdentity(stamp).sameDirectory(as: Filesystem.childStamp(
            input.assetsDirectoryName, in: parent.descriptor
        )) else { throw ExportError.unsafePublication }
        return handle
    }

    func begin(priorDigest: Data?) throws -> Stage? {
        guard journal.pending == nil else { throw ExportError.unsafePublication }
        let needsResources: Bool = switch input.mode {
        case .selfContained: false
        case .standalone: !input.resources.isEmpty
        }
        guard let previous = try priorState(needsResources: needsResources) else { return nil }
        let next = try makeIntent(previous, priorDigest: priorDigest, needsResources: needsResources)
        try journal.save(next)
        try checkpoint("intent-saved")
        directory = previous.directory
        try checkState(expectedDigest: priorDigest)
        if directory == nil {
            try createDirectory()
        }
        guard let directory else { throw ExportError.unsafePublication }
        hooks.afterCompanionDirectoryOpened?()
        try checkState(expectedDigest: priorDigest)
        try verifyMarker(in: directory.descriptor)
        if needsResources {
            try stageResources()
        }
        return try currentStage(includeResources: needsResources)
    }

    private struct PriorState {
        let directory: Filesystem.DirectoryHandle?
        let inventory: ExportCompanionAuthentication.AuthenticatedInventory?
    }

    private func priorState(needsResources: Bool) throws -> PriorState? {
        let existing: Filesystem.DirectoryHandle? = if needsResources {
            try openDirectory()
        } else {
            // Empty/self-contained output has never claimed unfamiliar siblings.
            try? openDirectory()
        }
        let inventory: ExportCompanionAuthentication.AuthenticatedInventory?
        if let existing {
            if needsResources {
                try verifyMarker(in: existing.descriptor)
                inventory = try loadInventory(in: existing.descriptor)
            } else {
                guard (try? verifyMarker(in: existing.descriptor)) != nil,
                      let known = try? loadInventory(in: existing.descriptor) else { return nil }
                inventory = known
            }
        } else {
            guard needsResources else { return nil }
            inventory = nil
        }
        return PriorState(directory: existing, inventory: inventory)
    }

    private func makeIntent(_ previous: PriorState, priorDigest: Data?, needsResources: Bool) throws -> Record {
        let inventory = previous.inventory
        let existing = previous.directory
        let priorKnown = priorDigest == nil || (inventory?.value.primaryDigest == priorDigest
            && inventory?.value.referencesKnown == true)
        var next = Record(
            binding: journal.binding, assetsName: input.assetsDirectoryName, priorDigest: priorDigest,
            desiredDigest: Data(SHA256.hash(data: input.bytes)), priorReferencesKnown: priorKnown,
            priorRequiredNames: priorKnown ? inventory?.value.requiredNames ?? [] : [],
            desiredReferencesKnown: input.referencesKnown,
            requiredNames: needsResources ? Array(Set(input.resources.map(\.identity.fileName))).sorted() : [],
            retireObsoleteResources: input.mode != .selfContained, createdDirectory: existing == nil
        )
        if let existing {
            next.directory = try ExportCompanionObjectIdentity(Filesystem.directoryStamp(existing.descriptor))
            next.previousInventory = inventory?.metadataReceipt.value
            next.owned = try retainedOwnership(inventory, in: existing.descriptor)
        }
        return next
    }

    private func createDirectory() throws {
        guard mkdirat(parent.descriptor, input.assetsDirectoryName, 0o700) == 0
        else { throw Filesystem.posixFailure() }
        guard fsync(parent.descriptor) == 0 else { throw Filesystem.posixFailure() }
        try checkpoint("directory-created")
        directory = try openDirectory()
        guard let directory else { throw ExportError.unsafePublication }
        try update { $0.directory = try ExportCompanionObjectIdentity(Filesystem.directoryStamp(
            directory.descriptor
        )) }
        try checkpoint("directory-recorded")
        let owner = try ExportAssetOwnerMarker.bytes(primary: input.url.lastPathComponent,
                                                     assets: input.assetsDirectoryName)
        _ = try install(owner, named: ExportFileWriter.markerFileName, role: .marker, mimeType: nil)
    }

    func verifyMarker(in descriptor: Int32) throws {
        let expected = try ExportAssetOwnerMarker.bytes(primary: input.url.lastPathComponent,
                                                        assets: input.assetsDirectoryName)
        guard try Filesystem.existingBytes(expected, named: ExportFileWriter.markerFileName, in: descriptor) != nil
        else { throw ExportError.unsafePublication }
    }

    func loadInventory(in descriptor: Int32) throws -> ExportCompanionAuthentication.AuthenticatedInventory? {
        let name = ExportCompanionInventoryRecord.fileName
        guard let bytes = try Filesystem.readBoundedFile(name, in: descriptor,
                                                         maxBytes: ExportCompanionLimits.envelopeBytes)
        else { return nil }
        return try journal.authentication.open(bytes, metadata: Filesystem.childStamp(name, in: descriptor),
                                               directory: Filesystem.directoryStamp(descriptor))
    }

    private func retainedOwnership(
        _ inventory: ExportCompanionAuthentication.AuthenticatedInventory?, in descriptor: Int32
    ) throws -> [Entry] {
        guard let inventory else { return [] }
        var result: [Entry] = []
        for entry in inventory.value.owned {
            let receipt = try ExportOwnedFileReceipt(authenticatedCompanion: inventory.receipt(named: entry.name))
            guard let actual = try ExportCompanionFiles.stamp(entry.name, in: descriptor),
                  actual == receipt.stamp else { continue }
            do {
                try protection.admission.checkRecoveryObject(actual)
                if try ExportReceiptInspection.verify(receipt, name: entry.name, in: descriptor) {
                    result.append(entry)
                }
            } catch { continue } // Changed/unreadable/adopted files lose cleanup eligibility.
        }
        return result
    }
}
