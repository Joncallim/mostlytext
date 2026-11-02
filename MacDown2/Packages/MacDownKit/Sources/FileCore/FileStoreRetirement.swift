import CryptoKit
import Darwin
import Foundation

/// In-memory permission to retire a known object, borrowed from a live save
/// stage. Its bytes come from our write or the caller-approved old baseline.
struct FileStoreRetirement {
    let directory: Int32
    let name: String
    let url: URL
    let digest: String
    let receipt: stat

    init(directory: Int32, name: String, url: URL, digest: String, receipt: stat) {
        self.directory = directory
        self.name = name
        self.url = url
        self.digest = digest
        self.receipt = receipt
    }

    init(approved revision: FileRevision, directory: Int32, name: String, url: URL) throws {
        var info = stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw Self.posixFailure() }
        // FileRevision uses Foundation's Date conversion. Reconstructing a
        // floating-point Date from stat nanoseconds can round differently.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modified = attributes[.modificationDate] as? Date
        let identity = PhysicalFileIdentity.FileObjectID(volume: String(info.st_dev), file: String(info.st_ino))
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size == revision.fileSize,
              identity == revision.fileObjectID, modified == revision.modificationDate,
              try Self.matchesBytesAndName(info, name: name, directory: directory, digest: revision.sha256)
        else { throw FileStoreError.fileChangedDuringRead }
        self.init(directory: directory, name: name, url: url, digest: revision.sha256, receipt: info)
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
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
            guard try Self.matchesBytesAndName(isolated, name: quarantine, directory: directory, digest: digest) else {
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

    static func matchesBytesAndName(_ expected: stat, name: String, directory: Int32, digest: String) throws -> Bool {
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
        return total == before.st_size && Self.hex(hasher.finalize()) == digest
            && fstat(reader, &after) == 0 && Self.sameMetadata(before, after, includingChangeTime: true)
            && fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0
            && Self.sameMetadata(before, named, includingChangeTime: true)
    }

    static func sameObject(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
            && lhs.st_birthtimespec.tv_sec == rhs.st_birthtimespec.tv_sec
            && lhs.st_birthtimespec.tv_nsec == rhs.st_birthtimespec.tv_nsec
    }

    static func sameMetadata(_ lhs: stat, _ rhs: stat, includingChangeTime: Bool) -> Bool {
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
