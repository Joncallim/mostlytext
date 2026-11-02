import CryptoKit
import Darwin
import Foundation

/// A live, exclusively created save stage. A pathname alone never authorizes
/// deletion: retirement requires this object's identity and known encoded bytes.
final class FileStoreStage {
    private let directory: Int32
    private let descriptor: Int32
    private let name: String
    private let url: URL
    private let digest: String
    private var receipt: stat

    init(bytes: Data, at url: URL) throws {
        self.url = url
        name = url.lastPathComponent
        digest = FileStoreRetirement.hex(SHA256.hash(data: bytes))
        directory = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { throw Self.posixFailure() }
        descriptor = openat(directory, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o666)
        guard descriptor >= 0 else {
            let failure = Self.posixFailure()
            _ = Darwin.close(directory)
            throw failure
        }
        receipt = stat()
        do {
            try bytes.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(
                        descriptor,
                        buffer.baseAddress?.advanced(by: offset),
                        buffer.count - offset
                    )
                    if count < 0, errno == EINTR {
                        continue
                    }
                    guard count > 0 else { throw Self.posixFailure() }
                    offset += count
                }
            }
            guard fstat(descriptor, &receipt) == 0,
                  receipt.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), receipt.st_size == bytes.count
            else { throw Self.posixFailure() }
            try refreshAfterMetadata()
        } catch {
            // Partial/unverified stages are retained. The caller surfaces their
            // location instead of granting cleanup authority from a failed init.
            // All stored properties are initialized: deinit owns descriptor
            // closure on this throwing path as well as successful instances.
            throw error
        }
    }

    deinit {
        _ = Darwin.close(descriptor)
        _ = Darwin.close(directory)
    }

    /// Metadata copying may change permission/ACL/xattr timestamps, but it may
    /// not substitute a different object or change the known encoded bytes.
    func refreshAfterMetadata() throws {
        var current = stat()
        guard fstat(descriptor, &current) == 0,
              FileStoreRetirement.sameObject(current, receipt), current.st_size == receipt.st_size,
              try matchesBytesAndName(current, name: name)
        else { throw FileStoreError.conditionalPublicationRecoveryRequired(url) }
        receipt = current
    }

    /// The conditional publisher has completed its own exchange and rollback.
    /// Only the rename's ctime change is admitted; bytes and other metadata
    /// must still match the original created stage.
    func refreshAfterRollback() throws {
        var current = stat()
        guard fstat(descriptor, &current) == 0,
              FileStoreRetirement.sameMetadata(current, receipt, includingChangeTime: false),
              try matchesBytesAndName(current, name: name)
        else { throw FileStoreError.conditionalPublicationRecoveryRequired(url) }
        receipt = current
    }

    func verifyBeforePublication() throws {
        guard try matchesBytesAndName(receipt, name: name) else {
            throw FileStoreError.conditionalPublicationRecoveryRequired(url)
        }
    }

    func retire(afterQuarantine: ((URL) throws -> Void)? = nil) throws {
        try FileStoreRetirement(directory: directory, name: name, url: url,
                                digest: digest, receipt: receipt).retire(afterQuarantine: afterQuarantine)
    }

    func approvedDisplacedRetirement(_ revision: FileRevision) throws -> FileStoreRetirement {
        try FileStoreRetirement(approved: revision, directory: directory, name: name, url: url)
    }

    private func matchesBytesAndName(_ expected: stat, name: String) throws -> Bool {
        try FileStoreRetirement.matchesBytesAndName(expected, name: name, directory: directory, digest: digest)
    }

    private static func posixFailure() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

extension FileStore {
    func failAfterStageCleanup(_ stage: FileStoreStage?, temporaryURL: URL,
                               error: any Error) throws(FileStoreError) -> Never {
        let mapped = mapWriteError(error)
        // The conditional publisher already preserved a competing object.
        if case .conditionalPublicationRecoveryRequired = mapped {
            throw mapped
        }
        if let stage {
            do { try stage.retire() } catch { throw mapWriteError(error) }
        } else if FileManager.default.fileExists(atPath: temporaryURL.path) {
            throw .conditionalPublicationRecoveryRequired(temporaryURL)
        }
        throw mapped
    }
}
