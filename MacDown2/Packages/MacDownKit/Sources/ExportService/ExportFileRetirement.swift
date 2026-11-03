import Darwin
import Foundation

enum ExportFileRetirement {
    private typealias Filesystem = ExportPublicationFilesystem

    static func retire(_ receipt: ExportOwnedFileReceipt, name: String, in directory: Int32,
                       protection: ExportRecoveryProtection? = nil,
                       afterQuarantine: ((String) -> Void)? = nil) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.utf8.contains(0), !name.utf8.contains(UInt8(ascii: "/"))
        else { throw ExportError.unsafePublication }
        try protection?.admission.checkRecoveryObject(receipt.stamp)
        guard let current = try Filesystem.primaryBaseline(name, in: directory) else { return }
        guard current == receipt.stamp else { throw ExportError.unsafePublication }
        let parts = name.split(separator: "-")
        let prefix = parts.count > 2 && parts[1].utf8.count == 64 ? ".mt-" + parts[1] + "-" : ".mt-"
        let quarantine = prefix + UUID().uuidString + ".retired"
        guard try moveToQuarantine(name, as: quarantine, receipt: receipt, in: directory, protection: protection)
        else { return }
        do {
            let quarantined = try Filesystem.childStamp(quarantine, in: directory)
            guard receipt.matchesMetadata(quarantined) else { throw ExportError.unsafePublication }
            afterQuarantine?(quarantine)
            guard try ExportReceiptInspection.verify(receipt, name: quarantine, in: directory, matching: quarantined)
            else { throw ExportError.unsafePublication }
            try ExportRecoveryProtection.mutate(receipt.stamp, protection: protection) {
                guard try Filesystem.childStamp(quarantine, in: directory) == quarantined
                else { throw ExportError.unsafePublication }
                guard unlinkat(directory, quarantine, 0) == 0 else { throw Filesystem.posixFailure() }
            }
        } catch {
            try restoreQuarantine(quarantine, as: name, in: directory, protection: protection)
            throw error
        }
    }

    /// Only a retirement that performed this rename may call restoration.
    /// A newly adopted current object remains at its quarantine path.
    static func restoreQuarantine(_ quarantine: String, as original: String, in directory: Int32,
                                  protection: ExportRecoveryProtection?) throws {
        let restore = {
            guard renameatx_np(directory, quarantine, directory, original, UInt32(RENAME_EXCL)) == 0
            else { throw Filesystem.recoveryRequired(directory: directory, name: quarantine) }
        }
        do {
            if let protection {
                try protection.lease.withRecoveryCutoff {
                    let current = try Filesystem.childStamp(quarantine, in: directory)
                    try protection.admission.checkRecoveryObject(current)
                    try restore()
                }
            } else {
                try restore()
            }
        } catch { throw Filesystem.recoveryRequired(directory: directory, name: quarantine) }
    }

    private static func moveToQuarantine(_ name: String, as quarantine: String, receipt: ExportOwnedFileReceipt,
                                         in directory: Int32, protection: ExportRecoveryProtection?) throws -> Bool {
        try ExportRecoveryProtection.mutate(receipt.stamp, protection: protection) {
            if renameatx_np(directory, name, directory, quarantine, UInt32(RENAME_EXCL)) == 0 {
                return true
            }
            if errno == ENOENT {
                return false
            }
            throw Filesystem.posixFailure()
        }
    }
}
