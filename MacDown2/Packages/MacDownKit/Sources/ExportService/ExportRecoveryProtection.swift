import Foundation

/// Reuses the existing document-publication ordering for owned working files.
/// Hashing and directory synchronization must remain outside this cutoff.
struct ExportRecoveryProtection: Sendable {
    let admission: ExportDestinationAdmission
    let lease: ExportLifetimeLease

    func withCutoff<T>(_ stamp: ExportPublicationFilesystem.Stamp, _ body: () throws -> T) throws -> T {
        try lease.withRecoveryCutoff {
            try admission.checkRecoveryObject(stamp)
            return try body()
        }
    }

    static func mutate<T>(_ stamp: ExportPublicationFilesystem.Stamp, protection: Self?,
                          _ body: () throws -> T) throws -> T {
        if let protection {
            return try protection.withCutoff(stamp, body)
        }
        return try body()
    }
}
