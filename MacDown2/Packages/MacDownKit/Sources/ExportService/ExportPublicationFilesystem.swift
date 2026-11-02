import Darwin
import Foundation

/// One bounded no-follow filesystem implementation for HTML publication.
enum ExportPublicationFilesystem {
    final class DirectoryHandle {
        let descriptor: Int32

        init(_ descriptor: Int32) {
            self.descriptor = descriptor
        }

        deinit {
            _ = Darwin.close(descriptor)
        }
    }

    struct Stamp: Equatable {
        let device: UInt64
        let inode: UInt64
        let kind: mode_t
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        init(_ info: stat) {
            device = UInt64(truncatingIfNeeded: info.st_dev)
            inode = UInt64(info.st_ino)
            kind = info.st_mode & mode_t(S_IFMT)
            size = info.st_size
            modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
            changedSeconds = Int64(info.st_ctimespec.tv_sec)
            changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
        }

        func sameDirectory(as other: Stamp) -> Bool {
            kind == mode_t(S_IFDIR) && other.kind == kind
                && device == other.device && inode == other.inode
        }
    }

    static func directoryStamp(_ descriptor: Int32) throws -> Stamp {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixFailure() }
        let stamp = Stamp(info)
        guard stamp.kind == mode_t(S_IFDIR) else { throw ExportError.unsafePublication }
        return stamp
    }

    static func childStamp(_ name: String, in directory: Int32) throws -> Stamp {
        var info = stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixFailure() }
        return Stamp(info)
    }

    static func primaryBaseline(_ name: String, in directory: Int32) throws -> Stamp? {
        var info = stat()
        if fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT {
                return nil
            }
            throw posixFailure()
        }
        let stamp = Stamp(info)
        guard stamp.kind == mode_t(S_IFREG) else { throw ExportError.unsafePublication }
        return stamp
    }

    static func readBoundedFile(_ name: String, in directory: Int32, maxBytes: Int) throws -> Data? {
        guard maxBytes >= 0, maxBytes <= ExportResourceBudget.maxFinalHTMLUTF8Bytes
        else { throw BoundedExportHTML.tooLarge }
        let descriptor = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {
                return nil
            }
            throw ExportError.unsafePublication
        }
        defer { _ = Darwin.close(descriptor) }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0 else { throw posixFailure() }
        let stamp = Stamp(initial)
        guard stamp.kind == mode_t(S_IFREG), stamp.size >= 0 else { throw ExportError.unsafePublication }
        guard stamp.size <= maxBytes else { throw BoundedExportHTML.tooLarge }
        let bytes = try readBoundedBytes(from: descriptor, maxBytes: maxBytes, expectedSize: Int(stamp.size))
        var final = stat()
        guard fstat(descriptor, &final) == 0, Stamp(final) == stamp,
              bytes.count == stamp.size, try childStamp(name, in: directory) == stamp
        else { throw ExportError.unsafePublication }
        return bytes
    }

    private static func readBoundedBytes(from descriptor: Int32, maxBytes: Int, expectedSize: Int) throws -> Data {
        var bytes = Data()
        bytes.reserveCapacity(expectedSize)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let remaining = maxBytes - bytes.count
            let wanted = remaining >= buffer.count ? buffer.count : remaining + 1
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, wanted) }
            if count < 0, errno == EINTR {
                continue
            }
            guard count >= 0 else { throw posixFailure() }
            if count == 0 {
                break
            }
            guard count <= remaining else { throw BoundedExportHTML.tooLarge }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        return bytes
    }

    static func childDirectory(_ name: String, in parent: Int32, matches expected: Stamp) throws -> Bool {
        try childStamp(name, in: parent).sameDirectory(as: expected)
    }

    static func directoryAtPath(_ path: String, matches expected: Stamp) throws -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw posixFailure() }
        return Stamp(info).sameDirectory(as: expected)
    }

    static func existingBytes(
        _ expected: Data,
        named name: String,
        in directory: Int32,
        observingCancellation: Bool = true
    ) throws -> Stamp? {
        // Non-blocking open prevents a substituted FIFO from waiting forever
        // before fstat can reject its non-regular inode.
        let descriptor = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {
                return nil
            }
            throw ExportError.unsafePublication
        }
        defer { _ = Darwin.close(descriptor) }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0 else { throw posixFailure() }
        let stamp = Stamp(initial)
        guard stamp.kind == mode_t(S_IFREG), stamp.size == expected.count
        else { throw ExportError.unsafePublication }
        var actual = Data()
        actual.reserveCapacity(expected.count)
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while actual.count < expected.count {
            if observingCancellation {
                try Task.checkCancellation()
            }
            let count = min(buffer.count, expected.count - actual.count)
            let readCount = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, count) }
            if readCount < 0, errno == EINTR {
                continue
            }
            guard readCount > 0 else { throw ExportError.unsafePublication }
            actual.append(contentsOf: buffer.prefix(readCount))
        }
        var extra: UInt8 = 0
        guard Darwin.read(descriptor, &extra, 1) == 0, actual == expected else {
            throw ExportError.unsafePublication
        }
        var final = stat()
        guard fstat(descriptor, &final) == 0, Stamp(final) == stamp else {
            throw ExportError.unsafePublication
        }
        return stamp
    }

    static func writeAll(_ bytes: Data, to descriptor: Int32, progress: inout Int) throws {
        try bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            while progress < buffer.count {
                try Task.checkCancellation()
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: progress),
                    min(64 * 1024, buffer.count - progress)
                )
                if written < 0, errno == EINTR {
                    continue
                }
                guard written > 0 else { throw posixFailure() }
                progress += written
            }
        }
    }

    static func retireTemporary(_ bytes: Data, name: String, expected: Stamp, in directory: Int32,
                                afterQuarantine: ((String) -> Void)? = nil) throws {
        let parts = name.split(separator: "-")
        let prefix = parts.count > 2 && parts[1].utf8.count == 64 ? ".mt-" + parts[1] + "-" : ".mt-"
        let quarantine = prefix + UUID().uuidString + ".retired"
        guard renameatx_np(directory, name, directory, quarantine, UInt32(RENAME_EXCL)) == 0 else {
            if errno == ENOENT {
                return
            }
            throw posixFailure()
        }
        afterQuarantine?(quarantine)
        do {
            guard let actual = try existingBytes(bytes, named: quarantine, in: directory, observingCancellation: false),
                  actual.device == expected.device, actual.inode == expected.inode, actual.kind == expected.kind
            else { throw ExportError.unsafePublication }
            guard unlinkat(directory, quarantine, 0) == 0 else { throw posixFailure() }
        } catch {
            // Never overwrite a writer that occupied the original name during inspection.
            guard renameatx_np(directory, quarantine, directory, name, UInt32(RENAME_EXCL)) == 0
            else { throw recoveryRequired(directory: directory, name: quarantine) }
            throw error
        }
    }

    static func posixFailure() -> ExportError {
        .writeFailed(underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
    }

    static func withScratch<T>(
        _ bytes: Data, name: String, in directory: Int32, retainOnSuccess: Bool,
        use: (Int32, Stamp) throws -> T
    ) throws -> T {
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { throw posixFailure() }
        defer { _ = Darwin.close(descriptor) }
        var progress = 0
        let result: T
        let stamp: Stamp
        do {
            try writeAll(bytes, to: descriptor, progress: &progress)
            guard fsync(descriptor) == 0 else { throw posixFailure() }
            var info = stat()
            guard fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
            else { throw ExportError.unsafePublication }
            stamp = Stamp(info)
            result = try use(descriptor, stamp)
        } catch {
            try cleanupTemporary(Data(bytes.prefix(progress)), name: name, descriptor: descriptor, in: directory)
            throw error
        }
        if !retainOnSuccess {
            try retireTemporary(bytes, name: name, expected: stamp, in: directory)
        }
        return result
    }

    static func cleanupTemporary(_ bytes: Data, name: String, descriptor: Int32, in directory: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixFailure() }
        try retireTemporary(bytes, name: name, expected: Stamp(info), in: directory)
    }

    private static func recoveryRequired(directory: Int32, name: String) -> ExportError {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let result = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let pointer = raw.baseAddress else { return -1 }
            return fcntl(directory, F_GETPATH, pointer)
        }
        guard result == 0, let path = String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
        else { return .unsafePublication }
        return .publicationRecoveryRequired(URL(fileURLWithPath: path).appendingPathComponent(name))
    }
}
