import CryptoKit
import Darwin
import Foundation

/// Descriptor-relative private storage; never provisions a missing key in an
/// already existing directory. All callers hold the stable process lock.
enum ExportJournalStorage {
    typealias Filesystem = ExportPublicationFilesystem

    enum RecordLimit {
        case primary
        case companion

        var maximumBytes: Int {
            switch self {
            case .primary: ExportJournalStore.maximumBytes
            case .companion: ExportCompanionLimits.envelopeBytes
            }
        }
    }

    static func open(_ location: ExportRecoveryLocation) throws -> Filesystem.DirectoryHandle {
        let url = location.directory
        guard url.isFileURL, url.query == nil, url.fragment == nil, !url.path.utf8.contains(0),
              url.lastPathComponent != ".", url.lastPathComponent != "..", !url.lastPathComponent.isEmpty
        else { throw ExportError.unsafePublication }
        let parent = Darwin.open(url.deletingLastPathComponent().path,
                                 O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw ExportError.unsafePublication }
        defer { Darwin.close(parent) }
        let created = mkdirat(parent, url.lastPathComponent, 0o700) == 0
        if !created, errno != EEXIST {
            throw Filesystem.posixFailure()
        }
        let descriptor = openat(parent, url.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ExportError.unsafePublication }
        let directory = Filesystem.DirectoryHandle(descriptor)
        try validate(descriptor, kind: mode_t(S_IFDIR), mode: 0o700)
        guard try Filesystem.childDirectory(url.lastPathComponent, in: parent,
                                            matches: Filesystem.directoryStamp(descriptor))
        else { throw ExportError.unsafePublication }
        if created {
            // Provisioning itself is fail-closed: a crash before a complete key
            // leaves an unavailable store, never an invitation to adopt residue.
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            try create(key, name: "producer.key", in: descriptor)
            guard fsync(descriptor) == 0, fsync(parent) == 0 else { throw Filesystem.posixFailure() }
        }
        return directory
    }

    static func lock(_ directory: Int32) throws -> Filesystem.DirectoryHandle {
        let descriptor = openat(
            directory,
            "producer.lock",
            O_RDWR | O_CREAT | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else { throw ExportError.unsafePublication }
        let handle = Filesystem.DirectoryHandle(descriptor)
        try validate(descriptor, kind: mode_t(S_IFREG), mode: 0o600)
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw ExportError.unsafePublication }
        guard try Filesystem.childStamp("producer.lock", in: directory) == fileStamp(descriptor)
        else { throw ExportError.unsafePublication }
        return handle // closing the descriptor releases flock
    }

    static func checkAuthority(directory: Int32, lock: Int32) throws {
        try validate(directory, kind: mode_t(S_IFDIR), mode: 0o700)
        try validate(lock, kind: mode_t(S_IFREG), mode: 0o600)
        guard try Filesystem.childStamp("producer.lock", in: directory) == fileStamp(lock)
        else { throw ExportError.unsafePublication }
    }

    static func read(_ name: String, in directory: Int32, maximum: Int,
                     limit: RecordLimit = .primary) throws -> Data? {
        let descriptor = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {
                return nil
            }
            throw ExportError.unsafePublication
        }
        defer { Darwin.close(descriptor) }
        try validate(descriptor, kind: mode_t(S_IFREG), mode: 0o600)
        let stamp = try fileStamp(descriptor)
        guard maximum >= 0, maximum <= limit.maximumBytes,
              stamp.size >= 0, stamp.size <= maximum else { throw ExportError.unsafePublication }
        let bytes = try readBytes(descriptor, maximum: maximum)
        guard bytes.count == stamp.size, try fileStamp(descriptor) == stamp, try Filesystem.childStamp(
            name,
            in: directory
        ) == stamp
        else { throw ExportError.unsafePublication }
        return bytes
    }

    static func replace(_ bytes: Data, named name: String, previous: Data?,
                        in directory: Int32, limit: RecordLimit = .primary) throws -> Filesystem.Stamp {
        guard bytes.count <= limit.maximumBytes else { throw ExportError.unsafePublication }
        try checkAggregate(directory, reserving: bytes.count)
        let temporary = ".mt-" + UUID().uuidString + ".journal"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Filesystem.posixFailure() }
        defer { Darwin.close(descriptor) }
        var progress = 0
        do {
            try validate(descriptor, kind: mode_t(S_IFREG), mode: 0o600)
            try writeBytes(bytes, to: descriptor, progress: &progress, maximum: limit.maximumBytes)
            guard fsync(descriptor) == 0 else { throw Filesystem.posixFailure() }
            if let previous {
                guard try read(name, in: directory, maximum: limit.maximumBytes, limit: limit) == previous
                else { throw ExportError.unsafePublication }
                guard renameat(directory, temporary, directory, name) == 0 else { throw Filesystem.posixFailure() }
            } else {
                guard renameatx_np(directory, temporary, directory, name, UInt32(RENAME_EXCL)) == 0
                else { throw Filesystem.posixFailure() }
            }
            guard fsync(directory) == 0 else { throw Filesystem.posixFailure() }
            return try fileStamp(descriptor)
        } catch {
            try Filesystem.cleanupTemporary(Data(bytes.prefix(progress)), name: temporary,
                                            descriptor: descriptor, in: directory)
            throw error
        }
    }

    static func checkCount(_ descriptor: Int32, reserving: Int = 1) throws {
        guard (1 ... 2).contains(reserving) else { throw ExportError.unsafePublication }
        // A fresh open file description avoids readdir offsets shared by dup.
        let copied = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copied >= 0 else { throw Filesystem.posixFailure() }
        guard let directory = fdopendir(copied) else {
            Darwin.close(copied)
            throw Filesystem.posixFailure()
        }
        defer { closedir(directory) }
        var count = 0
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw Filesystem.posixFailure() }
                return
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) { Array($0.prefix { $0 != 0 }) }
            if name == Array(".".utf8) || name == Array("..".utf8) {
                continue
            }
            count += 1
            guard count <= 1024 - reserving else { throw ExportError.unsafePublication }
        }
    }

    static func checkAggregate(_ descriptor: Int32, reserving bytes: Int) throws {
        guard bytes >= 0, bytes <= ExportCompanionLimits.envelopeBytes else { throw ExportError.unsafePublication }
        let copied = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copied >= 0 else { throw Filesystem.posixFailure() }
        guard let directory = fdopendir(copied) else {
            Darwin.close(copied)
            throw Filesystem.posixFailure()
        }
        defer { closedir(directory) }
        var total = bytes
        var count = 0
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw Filesystem.posixFailure() }
                return
            }
            let raw = withUnsafeBytes(of: entry.pointee.d_name) { Array($0.prefix { $0 != 0 }) }
            if raw == Array(".".utf8) || raw == Array("..".utf8) {
                continue
            }
            guard let name = String(bytes: raw, encoding: .utf8) else { throw ExportError.unsafePublication }
            count += 1
            let stamp = try Filesystem.childStamp(name, in: descriptor)
            guard count <= 1024, stamp.kind == mode_t(S_IFREG), stamp.size >= 0,
                  stamp.size <= ExportCompanionLimits.envelopeBytes,
                  let size = Int(exactly: stamp.size), total <= ExportCompanionLimits.privateBytes - size
            else { throw ExportError.unsafePublication }
            total += size
        }
    }

    private static func create(_ bytes: Data, name: String, in directory: Int32) throws {
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Filesystem.posixFailure() }
        defer { Darwin.close(descriptor) }
        try validate(descriptor, kind: mode_t(S_IFREG), mode: 0o600)
        var progress = 0
        try writeBytes(bytes, to: descriptor, progress: &progress)
        guard fsync(descriptor) == 0 else { throw Filesystem.posixFailure() }
    }

    /// Producer records and the key are bounded control data. Finish their
    /// checkpoint critical section even if cancellation arrives; otherwise a
    /// completed public stage could lose its only durable recovery receipt.
    /// Public source/resource reads and the promotion cutoff remain cancellable.
    private static func writeBytes(_ bytes: Data, to descriptor: Int32, progress: inout Int,
                                   maximum: Int = ExportJournalStore.maximumBytes) throws {
        guard bytes.count <= maximum else { throw ExportError.unsafePublication }
        try bytes.withUnsafeBytes { raw in
            while progress < raw.count {
                let count = Darwin.write(descriptor, raw.baseAddress?.advanced(by: progress), raw.count - progress)
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else { throw Filesystem.posixFailure() }
                progress += count
            }
        }
    }

    private static func readBytes(_ descriptor: Int32, maximum: Int) throws -> Data {
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: min(maximum + 1, 64 * 1024))
        while true {
            let remaining = maximum - bytes.count
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, remaining + 1))
            if count < 0, errno == EINTR {
                continue
            }
            guard count >= 0 else { throw Filesystem.posixFailure() }
            if count == 0 {
                return bytes
            }
            guard count <= remaining else { throw ExportError.unsafePublication }
            bytes.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func fileStamp(_ descriptor: Int32) throws -> Filesystem.Stamp {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw Filesystem.posixFailure() }
        return Filesystem.Stamp(info)
    }

    private static func validate(_ descriptor: Int32, kind: mode_t, mode: mode_t) throws {
        let stamp = try fileStamp(descriptor)
        var filesystem = statfs()
        guard fstatfs(descriptor, &filesystem) == 0, stamp.kind == kind, stamp.permissions == mode,
              stamp.owner == geteuid(), kind == mode_t(S_IFDIR) || stamp.links == 1,
              filesystem.f_flags & UInt32(MNT_IGNORE_OWNERSHIP | MNT_LOCAL) == UInt32(MNT_LOCAL)
        else { throw ExportError.unsafePublication }
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOATTR || errno == ENOENT {
                return
            }
            throw Filesystem.posixFailure()
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw ExportError.unsafePublication }
        var entry: acl_entry_t?
        var selector: Int32 = 0
        for _ in 0 ..< 1024 {
            if acl_get_entry(acl, selector, &entry) != 0 {
                guard errno == EINVAL else { throw ExportError.unsafePublication }
                return
            }
            guard let entry else { throw ExportError.unsafePublication }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0,
                  tag == ACL_EXTENDED_DENY else { throw ExportError.unsafePublication }
            selector = -1
        }
        throw ExportError.unsafePublication
    }
}
