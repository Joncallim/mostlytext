import Darwin
import Foundation

extension ThemeDirectory {
    struct StagedFile {
        let name: String
        let stored: ThemeStoredBytes
    }

    func stage(_ bytes: Data) throws -> StagedFile {
        guard bytes.count <= ThemeFile.maximumFileBytes else { throw ThemeStorageError.fileTooLarge }
        try checkRoot()
        let name = ".stage-" + UUID().uuidString.lowercased() + ".tmp"
        let file = openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard file >= 0 else { throw failure() }
        var created = stat()
        guard fstat(file, &created) == 0 else {
            let error = failure(); close(file); throw error
        }
        do {
            try write(bytes, to: file)
            guard flush(file) == 0 else { throw failure() }
        } catch {
            close(file)
            removePartialStage(name, identity: created)
            throw error
        }
        let closed = close(file)
        let closeError = errno
        guard closed == 0 else {
            removePartialStage(name, identity: created)
            throw ThemeStorageError.unavailable(closeError)
        }
        let stored: ThemeStoredBytes
        do {
            stored = try read(name)
        } catch {
            throw ThemeStorageError.recoveryRequired(fileName: name)
        }
        guard stored.fingerprint.device == Int64(created.st_dev), stored.fingerprint.inode == UInt64(created.st_ino),
              stored.bytes == bytes else { throw ThemeStorageError.recoveryRequired(fileName: name) }
        return StagedFile(name: name, stored: stored)
    }

    private func write(_ bytes: Data, to file: Int32) throws {
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let amount = Darwin.write(file, buffer.baseAddress.map { $0 + offset }, buffer.count - offset)
                if amount < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw failure()
                }
                guard amount > 0 else { throw ThemeStorageError.unavailable(EIO) }
                offset += amount
            }
        }
    }

    /// Only called for this operation's still-unpublished, incomplete file.
    private func removePartialStage(_ name: String, identity: stat) {
        var current = stat()
        if fstatat(descriptor, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
           current.st_dev == identity.st_dev, current.st_ino == identity.st_ino {
            _ = unlinkat(descriptor, name, 0)
        }
    }

    func removeOwnedStage(_ staged: StagedFile) -> Bool {
        guard let current = try? read(staged.name),
              current.fingerprint.matchesMovedObject(staged.stored.fingerprint) else { return false }
        return unlinkat(descriptor, staged.name, 0) == 0
    }

    func flush(_ file: Int32) -> Int32 {
        if let custom = hooks.flush {
            return custom(file)
        }
        if fcntl(file, F_FULLFSYNC) == 0 {
            return 0
        }
        guard [ENOTSUP, EINVAL, ENOTTY].contains(errno) else { return -1 }
        return fsync(file)
    }

    func publication(_ staged: StagedFile, preserved: String? = nil) -> ThemePublication {
        ThemePublication(bytes: staged.stored, durabilityWarning: flush(descriptor) != 0,
                         preservedStagingName: preserved, rootStillCurrent: (try? checkRoot()) != nil)
    }
}
