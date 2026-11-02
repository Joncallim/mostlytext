import Darwin
import Foundation

/// Actor-owned restricted journal storage. Failed stages are retained; this
/// owner never deletes a named file or replaces a published record.
final class MigrationJournalDirectory {
    static let maximumBytes = 256 * 1024
    let url: URL
    var directory: Int32 = -1
    var lock: Int32 = -1
    let checkpoint: (@Sendable (Checkpoint) throws -> Void)?

    enum Checkpoint: Sendable { case afterWrite, afterFileSync, afterRename, afterDirectorySync }

    init(url: URL, checkpoint: (@Sendable (Checkpoint) throws -> Void)? = nil) throws {
        self.url = url; self.checkpoint = checkpoint
        guard url.isFileURL, url.host == nil || url.host == "", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.hasPrefix("/"),
              !url.path.utf8.contains(0), url.pathComponents.allSatisfy({ $0 != "." && $0 != ".." }),
              !["", "/", ".", ".."].contains(url.lastPathComponent) else { throw LegacyMigrationFailure.unsafeStorage }
        do {
            let parent = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
            guard parent >= 0 else { throw LegacyMigrationFailure.unavailable(errno) }
            defer { Darwin.close(parent) }
            var attributes = stat()
            guard fstat(parent, &attributes) == 0, attributes.st_uid == geteuid(),
                  attributes.st_mode & 0o022 == 0 else {
                throw LegacyMigrationFailure.unsafeStorage
            }
            try validate(parent, kind: S_IFDIR, mode: attributes.st_mode & 0o7777)
            if mkdirat(parent, url.lastPathComponent, 0o700) != 0, errno != EEXIST {
                throw LegacyMigrationFailure.unavailable(errno)
            }
            directory = openat(parent, url.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directory >= 0 else { throw LegacyMigrationFailure.unsafeStorage }
            try validate(directory, kind: S_IFDIR, mode: 0o700)
            lock = openat(directory, "lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
            guard lock >= 0 else { throw LegacyMigrationFailure.unsafeStorage }
            try validate(lock, kind: S_IFREG, mode: 0o600)
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
                if errno == EWOULDBLOCK {
                    throw LegacyMigrationFailure.busy
                }
                throw LegacyMigrationFailure.unavailable(errno)
            }
            try verify()
        } catch { close(); throw error }
    }

    deinit { close() }

    func close() {
        if lock >= 0 {
            Darwin.close(lock); lock = -1
        }
        if directory >= 0 {
            Darwin.close(directory); directory = -1
        }
    }

    func verify() throws {
        guard directory >= 0, lock >= 0 else { throw LegacyMigrationFailure.changedStorage }
        let current = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard current >= 0 else { throw LegacyMigrationFailure.changedStorage }
        defer { Darwin.close(current) }
        try validate(current, kind: S_IFDIR, mode: 0o700)
        try validate(directory, kind: S_IFDIR, mode: 0o700)
        try validate(lock, kind: S_IFREG, mode: 0o600)
        guard try identity(current) == identity(directory),
              try namedIdentity("lock") == identity(lock) else { throw LegacyMigrationFailure.changedStorage }
    }

    func read(_ name: String) throws -> Data? {
        try verify()
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {
                return nil
            }
            throw LegacyMigrationFailure.unsafeStorage
        }
        defer { Darwin.close(descriptor) }
        try validate(descriptor, kind: S_IFREG, mode: 0o600)
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_size <= Self.maximumBytes else {
            throw LegacyMigrationFailure.invalidRecord
        }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 {
                break
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw LegacyMigrationFailure.unavailable(errno)
            }
            guard count <= Self.maximumBytes - bytes.count else { throw LegacyMigrationFailure.invalidRecord }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              bytes.count == after.st_size,
              try namedIdentity(name) == identity(descriptor) else { throw LegacyMigrationFailure.changedStorage }
        try verify()
        return bytes
    }

    func publish(_ bytes: Data, as name: String) throws {
        guard bytes.count <= Self.maximumBytes else { throw LegacyMigrationFailure.invalidRecord }
        if let existing = try read(name) {
            guard existing == bytes else { throw LegacyMigrationFailure.transactionExists }
            try resync(bytes, named: name)
            return
        }
        let stage = "stage-" + UUID().uuidString
        let descriptor = openat(directory, stage, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        defer { Darwin.close(descriptor) }
        try validate(descriptor, kind: S_IFREG, mode: 0o600)
        try write(bytes, to: descriptor)
        try checkpoint?(.afterWrite)
        try syncFile(descriptor)
        try checkpoint?(.afterFileSync)
        try verify()
        guard try namedIdentity(stage) == identity(descriptor) else { throw LegacyMigrationFailure.changedStorage }
        guard renameatx_np(directory, stage, directory, name, UInt32(RENAME_EXCL)) == 0 else {
            throw LegacyMigrationFailure.unavailable(errno)
        }
        try checkpoint?(.afterRename)
        guard fsync(directory) == 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        try checkpoint?(.afterDirectorySync)
        try verify()
        guard try namedIdentity(name) == identity(descriptor), try read(name) == bytes else {
            throw LegacyMigrationFailure.changedStorage
        }
    }

    func syncFile(_ descriptor: Int32) throws {
        guard fsync(descriptor) == 0,
              fcntl(descriptor, F_FULLFSYNC) == 0 else { throw LegacyMigrationFailure.unavailable(errno) }
    }
}
