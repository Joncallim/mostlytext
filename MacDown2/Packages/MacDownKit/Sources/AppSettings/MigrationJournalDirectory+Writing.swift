import Darwin
import Foundation

extension MigrationJournalDirectory {
    func resync(_ bytes: Data, named name: String) throws {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw LegacyMigrationFailure.changedStorage }
        defer { Darwin.close(descriptor) }
        try validate(descriptor, kind: S_IFREG, mode: 0o600)
        guard try namedIdentity(name) == identity(descriptor) else { throw LegacyMigrationFailure.changedStorage }
        try syncFile(descriptor)
        guard fsync(directory) == 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        try verify()
        guard try namedIdentity(name) == identity(descriptor), try read(name) == bytes else {
            throw LegacyMigrationFailure.changedStorage
        }
    }

    func write(_ bytes: Data, to descriptor: Int32) throws {
        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw LegacyMigrationFailure.unavailable(errno)
                }
                guard count > 0 else { throw LegacyMigrationFailure.unavailable(EIO) }
                offset += count
            }
        }
    }
}
