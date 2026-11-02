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
    private let digest: SHA256.Digest
    private var receipt: stat

    init(bytes: Data, at url: URL) throws {
        self.url = url
        name = url.lastPathComponent
        digest = SHA256.hash(data: bytes)
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
              Self.sameObject(current, receipt), current.st_size == receipt.st_size,
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
              Self.sameMetadata(current, receipt, includingChangeTime: false),
              try matchesBytesAndName(current, name: name)
        else { throw FileStoreError.conditionalPublicationRecoveryRequired(url) }
        receipt = current
    }

    func verifyBeforePublication() throws {
        guard try matchesBytesAndName(receipt, name: name) else {
            throw FileStoreError.conditionalPublicationRecoveryRequired(url)
        }
    }

    /// Rename first, then inspect the isolated object. A changed object is
    /// restored without replacement, or retained at the reported recovery URL.
    func retire(afterQuarantine: ((URL) throws -> Void)? = nil) throws {
        var named = stat()
        guard fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT {
                return
            }
            throw FileStoreError.conditionalPublicationRecoveryRequired(url)
        }
        guard Self.sameMetadata(named, receipt, includingChangeTime: true) else {
            throw FileStoreError.conditionalPublicationRecoveryRequired(url)
        }
        let quarantine = "." + UUID().uuidString + ".save-retired"
        let recovery = url.deletingLastPathComponent().appendingPathComponent(quarantine)
        guard renameatx_np(directory, name, directory, quarantine, UInt32(RENAME_EXCL)) == 0 else {
            if errno == ENOENT {
                return
            }
            throw FileStoreError.conditionalPublicationRecoveryRequired(url)
        }
        do {
            var isolated = stat()
            guard fstatat(directory, quarantine, &isolated, AT_SYMLINK_NOFOLLOW) == 0,
                  Self.sameMetadata(isolated, receipt, includingChangeTime: false)
            else { throw FileStoreError.fileChangedDuringRead }
            try afterQuarantine?(recovery)
            guard try matchesBytesAndName(isolated, name: quarantine) else {
                throw FileStoreError.fileChangedDuringRead
            }
            guard unlinkat(directory, quarantine, 0) == 0 else { throw Self.posixFailure() }
        } catch {
            if renameatx_np(directory, quarantine, directory, name, UInt32(RENAME_EXCL)) == 0 {
                throw FileStoreError.conditionalPublicationRecoveryRequired(url)
            }
            throw FileStoreError.conditionalPublicationRecoveryRequired(recovery)
        }
    }

    private func matchesBytesAndName(_ expected: stat, name: String) throws -> Bool {
        let reader = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard reader >= 0 else { return false }
        defer { _ = Darwin.close(reader) }
        var before = stat()
        guard fstat(reader, &before) == 0,
              before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), before.st_size >= 0,
              Self.sameMetadata(before, expected, includingChangeTime: true)
        else { return false }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var total: Int64 = 0
        while true {
            let remaining = before.st_size - total
            let wanted = remaining >= buffer.count ? buffer.count : Int(remaining) + 1
            let count = Darwin.read(reader, &buffer, wanted)
            if count < 0, errno == EINTR {
                continue
            }
            guard count >= 0 else { throw Self.posixFailure() }
            if count == 0 {
                break
            }
            guard count <= remaining else { return false }
            total += Int64(count)
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0.prefix(count))) }
        }
        var after = stat()
        var named = stat()
        return total == before.st_size && hasher.finalize() == digest
            && fstat(reader, &after) == 0 && Self.sameMetadata(before, after, includingChangeTime: true)
            && fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0
            && Self.sameMetadata(before, named, includingChangeTime: true)
    }

    private static func sameObject(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
            && lhs.st_birthtimespec.tv_sec == rhs.st_birthtimespec.tv_sec
            && lhs.st_birthtimespec.tv_nsec == rhs.st_birthtimespec.tv_nsec
    }

    private static func sameMetadata(_ lhs: stat, _ rhs: stat, includingChangeTime: Bool) -> Bool {
        sameObject(lhs, rhs) && lhs.st_mode == rhs.st_mode && lhs.st_size == rhs.st_size
            && lhs.st_uid == rhs.st_uid && lhs.st_gid == rhs.st_gid && lhs.st_nlink == rhs.st_nlink
            && lhs.st_flags == rhs.st_flags
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && (!includingChangeTime || (lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
                    && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec))
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
