import Darwin
import Foundation

enum ExportFileRetirement {
    private typealias Filesystem = ExportPublicationFilesystem

    static func retire(_ receipt: ExportOwnedFileReceipt, name: String, in directory: Int32,
                       afterQuarantine: ((String) -> Void)? = nil) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.utf8.contains(0), !name.utf8.contains(UInt8(ascii: "/"))
        else { throw ExportError.unsafePublication }
        guard let current = try Filesystem.primaryBaseline(name, in: directory) else { return }
        guard current == receipt.stamp else { throw ExportError.unsafePublication }
        let parts = name.split(separator: "-")
        let prefix = parts.count > 2 && parts[1].utf8.count == 64 ? ".mt-" + parts[1] + "-" : ".mt-"
        let quarantine = prefix + UUID().uuidString + ".retired"
        guard renameatx_np(directory, name, directory, quarantine, UInt32(RENAME_EXCL)) == 0 else {
            if errno == ENOENT {
                return
            }
            throw Filesystem.posixFailure()
        }
        do {
            let quarantined = try Filesystem.childStamp(quarantine, in: directory)
            guard receipt.matchesMetadata(quarantined) else { throw ExportError.unsafePublication }
            afterQuarantine?(quarantine)
            guard try ExportReceiptInspection.verify(receipt, name: quarantine, in: directory, matching: quarantined)
            else { throw ExportError.unsafePublication }
            guard unlinkat(directory, quarantine, 0) == 0 else { throw Filesystem.posixFailure() }
        } catch {
            guard renameatx_np(directory, quarantine, directory, name, UInt32(RENAME_EXCL)) == 0
            else { throw Filesystem.recoveryRequired(directory: directory, name: quarantine) }
            throw error
        }
    }
}
