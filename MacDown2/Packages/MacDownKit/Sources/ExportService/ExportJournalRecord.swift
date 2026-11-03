import CryptoKit
import Foundation

/// Serialization models carry no removal authority. Only the authenticated
/// store can turn an archived receipt into a receipt usable by retirement.
struct ExportJournalRecord: Codable {
    struct Binding: Codable, Equatable {
        let device: UInt64
        let inode: UInt64
        let birthSeconds: Int64
        let birthNanoseconds: Int64
        let leaf: Data

        init(parent: ExportPublicationFilesystem.Stamp, leaf: String) {
            device = parent.device
            inode = parent.inode
            birthSeconds = parent.birthSeconds
            birthNanoseconds = parent.birthNanoseconds
            self.leaf = Data(leaf.utf8)
        }

        var fileName: String {
            // JSON's explicit fields and base64 leaf avoid concatenation ambiguity.
            get throws {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                return try SHA256.hash(data: encoder.encode(self)).map { String(format: "%02x", $0) }.joined() + ".json"
            }
        }
    }

    struct Receipt: Codable {
        let stamp: ExportPublicationFilesystem.Stamp
        let digest: Data

        init(_ owned: ExportOwnedFileReceipt) {
            stamp = owned.stamp
            digest = owned.digest
        }
    }

    struct Pending: Codable {
        let operation: UUID
        let priorDigest: Data?
        let desiredDigest: Data
        let scratch: String
        let receipt: Receipt
        var quarantine: String?
    }

    let schema: Int
    let binding: Binding
    var pending: Pending?

    init(binding: Binding, pending: Pending? = nil) {
        schema = 1
        self.binding = binding
        self.pending = pending
    }
}
