import CryptoKit
import Darwin
import Foundation

/// An owned root descriptor, used only by its catalog actor. Opening child
/// names through this descriptor never derives authority from a pathname check.
final class ThemeDirectory: Sendable {
    let url: URL
    let descriptor: Int32
    let device: dev_t
    let inode: ino_t
    let hooks: ThemeStorageHooks

    init(url: URL, hooks: ThemeStorageHooks = .none) throws {
        guard url.isFileURL, url.host == nil || url.host == "", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw ThemeStorageError.invalidDirectory }
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY)
        guard descriptor >= 0 else { throw ThemeStorageError.invalidDirectory }
        var info = stat()
        var volume = statfs()
        guard fstat(descriptor, &info) == 0, fstatfs(descriptor, &volume) == 0,
              info.st_uid == geteuid(), info.st_mode & 0o077 == 0,
              volume.f_flags & UInt32(MNT_IGNORE_OWNERSHIP) == 0 else {
            close(descriptor)
            throw ThemeStorageError.invalidDirectory
        }
        guard (try? url.resourceValues(forKeys: [.volumeSupportsSwapRenamingKey]).volumeSupportsSwapRenaming) == true
        else {
            close(descriptor)
            throw ThemeStorageError.unsupportedAtomicPublication
        }
        self.url = url
        self.descriptor = descriptor
        device = info.st_dev
        inode = info.st_ino
        self.hooks = hooks
    }

    deinit { close(descriptor) }

    static func name(for id: UUID) -> String {
        id.uuidString.lowercased() + ".json"
    }

    func checkRoot() throws {
        let current = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY)
        guard current >= 0 else { throw ThemeStorageError.directoryChanged }
        defer { close(current) }
        var info = stat()
        var volume = statfs()
        guard fstat(current, &info) == 0, fstatfs(current, &volume) == 0,
              info.st_dev == device, info.st_ino == inode, info.st_uid == geteuid(), info.st_mode & 0o077 == 0,
              volume.f_flags & UInt32(MNT_IGNORE_OWNERSHIP) == 0 else { throw ThemeStorageError.directoryChanged }
    }

    func identifiers() throws -> [UUID] {
        try checkRoot()
        let scan = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard scan >= 0 else { throw failure() }
        guard let stream = fdopendir(scan) else {
            let error = failure(); close(scan); throw error
        }
        defer { closedir(stream) }
        var count = 0
        var identifiers: [UUID] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw failure() }
                break
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) { buffer in
                String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8) ?? ""
            }
            if name == "." || name == ".." {
                continue
            }
            count += 1
            guard count <= 1024 else { throw ThemeStorageError.tooManyDirectoryEntries }
            guard name.hasSuffix(".json"), let id = UUID(uuidString: String(name.dropLast(5))),
                  name == Self.name(for: id) else { continue }
            identifiers.append(id)
            guard identifiers.count <= ThemeCatalogSnapshot.maximumCustomThemes else {
                throw ThemeCatalogError.catalogFull
            }
        }
        try checkRoot()
        return identifiers.sorted { $0.uuidString < $1.uuidString }
    }

    func read(_ name: String) throws -> ThemeStoredBytes {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
            throw ThemeStorageError.unsafeFile
        }
        let file = openat(descriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else { throw failure() }
        defer { close(file) }
        var before = stat()
        guard fstat(file, &before) == 0 else { throw failure() }
        guard before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1,
              before.st_uid == geteuid() else { throw ThemeStorageError.unsafeFile }
        guard before.st_size >= 0, before.st_size <= ThemeFile.maximumFileBytes else {
            throw ThemeStorageError.fileTooLarge
        }
        let bytes = try boundedBytes(from: file)
        var after = stat()
        guard fstat(file, &after) == 0 else { throw failure() }
        guard metadataMatches(before, after), after.st_size == bytes.count else {
            throw ThemeStorageError.changedDuringRead
        }
        return ThemeStoredBytes(bytes: bytes, fingerprint: fingerprint(after, bytes: bytes))
    }

    private func boundedBytes(from file: Int32) throws -> Data {
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let amount = Darwin.read(file, &buffer, buffer.count)
            if amount < 0 {
                if errno == EINTR {
                    continue
                }
                throw failure()
            }
            if amount == 0 {
                break
            }
            guard amount <= ThemeFile.maximumFileBytes - bytes.count else { throw ThemeStorageError.fileTooLarge }
            bytes.append(contentsOf: buffer.prefix(amount))
            try hooks.afterReadChunk?(bytes.count)
        }
        return bytes
    }

    func fingerprint(_ info: stat, bytes: Data) -> ThemeFileFingerprint {
        ThemeFileFingerprint(
            device: Int64(info.st_dev), inode: UInt64(info.st_ino), byteCount: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec),
            digest: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        )
    }

    func metadataMatches(_ first: stat, _ second: stat) -> Bool {
        first.st_dev == second.st_dev && first.st_ino == second.st_ino && first.st_size == second.st_size
            && first.st_mtimespec.tv_sec == second.st_mtimespec.tv_sec
            && first.st_mtimespec.tv_nsec == second.st_mtimespec.tv_nsec
            && first.st_ctimespec.tv_sec == second.st_ctimespec.tv_sec
            && first.st_ctimespec.tv_nsec == second.st_ctimespec.tv_nsec
            && first.st_nlink == second.st_nlink && first.st_uid == second.st_uid && first.st_mode == second.st_mode
    }

    func failure() -> ThemeStorageError {
        .unavailable(errno)
    }
}
