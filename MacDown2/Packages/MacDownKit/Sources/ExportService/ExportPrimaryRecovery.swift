import CryptoKit
import Darwin
import Foundation

/// Recovery is limited to a fresh, explicitly selected destination. The real
/// primary must still match one of the two recorded transaction states.
enum ExportPrimaryRecovery {
    private typealias Filesystem = ExportPublicationFilesystem
    private struct Target {
        let primary: String
        let digest: Data?
        let directory: Int32
    }

    static func digest(of name: String, in directory: Int32) throws -> Data? {
        let descriptor = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {
                return nil
            }
            throw ExportError.unsafePublication
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw Filesystem.posixFailure() }
        let initial = Filesystem.Stamp(info)
        guard initial.kind == mode_t(S_IFREG), initial.size >= 0,
              initial.size <= ExportResourceBudget.maxFinalHTMLUTF8Bytes
        else { throw ExportError.unsafePublication }
        let digest = try ExportReceiptInspection.hash(descriptor, expectedBytes: Int(initial.size))
        guard fstat(descriptor, &info) == 0, Filesystem.Stamp(info) == initial,
              try Filesystem.childStamp(name, in: directory) == initial
        else { throw ExportError.unsafePublication }
        return Data(digest)
    }

    static func recover(_ store: ExportJournalStore, primary: String, in directory: Int32,
                        afterQuarantine: ((String) throws -> Void)? = nil) throws {
        guard let pending = store.record.pending else { return }
        let observed = try digest(of: primary, in: directory)
        guard observed == pending.priorDigest || observed == pending.desiredDigest
        else { throw Filesystem.recoveryRequired(directory: directory, name: pending.scratch) }
        let receipt = try store.ownedReceipt()
        // A recorded quarantine is authoritative only for this exact inode and
        // digest; its name alone never permits deletion or adoption.
        if let quarantine = pending.quarantine,
           let current = try Filesystem.primaryBaseline(quarantine, in: directory) {
            guard try Filesystem.primaryBaseline(pending.scratch, in: directory) == nil,
                  receipt.matchesMetadata(current),
                  try ExportReceiptInspection.verify(receipt, name: quarantine, in: directory, matching: current),
                  try digest(of: primary, in: directory) == observed
            else { throw Filesystem.recoveryRequired(directory: directory, name: quarantine) }
            try store.checkCurrent()
            try remove(quarantine, in: directory)
        } else {
            try retireScratch(store, pending: pending, receipt: receipt,
                              target: Target(primary: primary, digest: observed, directory: directory),
                              afterQuarantine: afterQuarantine)
        }
        try store.finish()
    }

    private static func retireScratch(_ store: ExportJournalStore, pending: ExportJournalRecord.Pending,
                                      receipt: ExportOwnedFileReceipt, target: Target,
                                      afterQuarantine: ((String) throws -> Void)?) throws {
        let directory = target.directory
        let primary = target.primary
        let expected = target.digest
        guard let current = try Filesystem.primaryBaseline(pending.scratch, in: directory) else { return }
        guard receipt.matchesMetadata(current),
              try ExportReceiptInspection.verify(receipt, name: pending.scratch, in: directory, matching: current)
        else { throw Filesystem.recoveryRequired(directory: directory, name: pending.scratch) }
        let quarantine = try store.prepareQuarantine()
        guard try digest(of: primary, in: directory) == expected,
              renameatx_np(directory, pending.scratch, directory, quarantine, UInt32(RENAME_EXCL)) == 0
        else { throw Filesystem.recoveryRequired(directory: directory, name: pending.scratch) }
        do {
            let quarantined = try Filesystem.childStamp(quarantine, in: directory)
            guard receipt.matchesMetadata(quarantined) else { throw ExportError.unsafePublication }
            try afterQuarantine?(quarantine)
            guard try ExportReceiptInspection.verify(receipt, name: quarantine, in: directory, matching: quarantined),
                  try digest(of: primary, in: directory) == expected
            else { throw ExportError.unsafePublication }
            try store.checkCurrent()
            try remove(quarantine, in: directory)
        } catch {
            guard renameatx_np(directory, quarantine, directory, pending.scratch, UInt32(RENAME_EXCL)) == 0
            else { throw Filesystem.recoveryRequired(directory: directory, name: quarantine) }
            throw error
        }
    }

    private static func remove(_ name: String, in directory: Int32) throws {
        guard unlinkat(directory, name, 0) == 0, fsync(directory) == 0 else { throw Filesystem.posixFailure() }
    }
}
