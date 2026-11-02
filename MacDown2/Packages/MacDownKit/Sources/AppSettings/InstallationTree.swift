import CryptoKit
import Darwin
import Foundation

struct InstallationFileIdentity: Codable, Sendable, Equatable {
    let device: Int64
    let inode: UInt64
    let size: Int64
    let mode: UInt16
    let modified: Int64
    let modifiedNanos: Int64
    let changed: Int64
    let changedNanos: Int64

    init(_ info: stat) {
        device = Int64(info.st_dev); inode = UInt64(info.st_ino); size = info.st_size
        mode = UInt16(info.st_mode)
        modified = Int64(info.st_mtimespec.tv_sec); modifiedNanos = Int64(info.st_mtimespec.tv_nsec)
        changed = Int64(info.st_ctimespec.tv_sec); changedNanos = Int64(info.st_ctimespec.tv_nsec)
    }
}

struct InstallationTreeEntry: Codable, Sendable {
    let path: String
    let directory: Bool
    let identity: InstallationFileIdentity
    let digest: String?
}

struct InstallationTreeSnapshot: Codable, Sendable {
    let root: InstallationFileIdentity?
    let entries: [InstallationTreeEntry]

    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// The actor owns all calls. Source paths are opened without following links;
/// child access is descriptor-relative and every read binds identity and bytes.
struct InstallationTree {
    static let maximumEntries = 512
    static let maximumFileBytes = 64 * 1024 * 1024
    static let maximumTotalBytes = 512 * 1024 * 1024
    let storage: MigrationJournalDirectory

    func snapshot(_ url: URL) throws -> InstallationTreeSnapshot {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {
                return InstallationTreeSnapshot(root: nil, entries: [])
            }
            throw LegacyMigrationFailure.unsafeStorage
        }
        defer { Darwin.close(descriptor) }
        let before = try info(descriptor, kind: S_IFDIR)
        var entries: [InstallationTreeEntry] = []
        var total = 0
        try scan(descriptor, prefix: "", entries: &entries, total: &total, depth: 0)
        guard try info(descriptor, kind: S_IFDIR) == before else { throw LegacyMigrationFailure.changedStorage }
        let named = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard named >= 0 else { throw LegacyMigrationFailure.changedStorage }
        defer { Darwin.close(named) }
        guard try info(named, kind: S_IFDIR) == before else { throw LegacyMigrationFailure.changedStorage }
        return InstallationTreeSnapshot(root: before, entries: entries)
    }

    private func scan(_ descriptor: Int32, prefix: String, entries: inout [InstallationTreeEntry],
                      total: inout Int, depth: Int) throws {
        guard depth <= 8 else { throw LegacyPreferenceSnapshotError.tooDeep }
        for name in try names(descriptor) {
            guard entries.count < Self.maximumEntries else { throw LegacyPreferenceSnapshotError.tooManyEntries }
            let path = prefix.isEmpty ? name : prefix + "/" + name
            guard path.utf8.count <= 1024 else { throw LegacyPreferenceSnapshotError.stringTooLong }
            let child = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard child >= 0 else { throw LegacyMigrationFailure.unsafeStorage }
            defer { Darwin.close(child) }
            var raw = stat()
            guard fstat(child, &raw) == 0 else { throw LegacyMigrationFailure.changedStorage }
            let isDirectory = raw.st_mode & S_IFMT == S_IFDIR
            let before = try info(child, kind: isDirectory ? S_IFDIR : S_IFREG)
            if isDirectory {
                entries.append(InstallationTreeEntry(path: path, directory: true, identity: before, digest: nil))
                try scan(child, prefix: path, entries: &entries, total: &total, depth: depth + 1)
            } else {
                let bytes = try read(child)
                guard bytes.count <= Self.maximumTotalBytes - total
                else { throw LegacyPreferenceSnapshotError.tooLarge }
                total += bytes.count
                entries.append(InstallationTreeEntry(path: path, directory: false, identity: before,
                                                     digest: LegacyEditorJournalPlan.digest(bytes)))
            }
            var named = stat()
            guard fstatat(descriptor, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  InstallationFileIdentity(named) == before,
                  try info(child, kind: isDirectory ? S_IFDIR : S_IFREG) == before
            else { throw LegacyMigrationFailure.changedStorage }
        }
    }

    func copy(
        _ snapshot: InstallationTreeSnapshot,
        from url: URL,
        into destination: Int32,
        workingCommands: Bool = false
    ) throws {
        guard let root = snapshot.root else { return }
        let source = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard source >= 0 else { throw LegacyMigrationFailure.changedStorage }
        defer { Darwin.close(source) }
        guard try info(source, kind: S_IFDIR) == root else { throw LegacyMigrationFailure.changedStorage }
        for entry in snapshot.entries {
            let parts = try components(entry.path)
            let parent = try openParent(source, components: Array(parts.dropLast()))
            defer { Darwin.close(parent) }
            let name = try last(parts)
            let descriptor = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw LegacyMigrationFailure.changedStorage }
            defer { Darwin.close(descriptor) }
            guard try info(descriptor, kind: entry.directory ? S_IFDIR : S_IFREG) == entry.identity else {
                throw LegacyMigrationFailure.changedStorage
            }
            if entry.directory {
                let created = try makeDirectory(destination, components: parts)
                Darwin.close(created)
            } else {
                let bytes = try read(descriptor)
                guard LegacyEditorJournalPlan.digest(bytes) == entry.digest
                else { throw LegacyMigrationFailure.changedStorage }
                try write(bytes, beneath: destination, components: parts,
                          mode: workingCommands && parts.first == "Commands" && entry.identity
                              .mode & 0o100 != 0 ? 0o700 : 0o600)
            }
        }
        guard try self.snapshot(url).encoded() == snapshot.encoded()
        else { throw LegacyMigrationFailure.changedStorage }
        try syncDirectories(destination)
    }

    func verifyCopy(_ snapshot: InstallationTreeSnapshot, beneath root: Int32, workingCommands: Bool = false) throws {
        for entry in snapshot.entries {
            let parts = try components(entry.path)
            let parent = try openParent(root, components: Array(parts.dropLast()))
            defer { Darwin.close(parent) }
            let child = try openat(parent, last(parts), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard child >= 0 else { throw LegacyMigrationFailure.changedStorage }
            defer { Darwin.close(child) }
            let mode: mode_t = entry.directory || (workingCommands && parts.first == "Commands"
                && entry.identity.mode & 0o100 != 0) ? 0o700 : 0o600
            try storage.validate(child, kind: entry.directory ? S_IFDIR : S_IFREG, mode: mode)
            if !entry.directory {
                guard try LegacyEditorJournalPlan.digest(read(child)) == entry.digest else {
                    throw LegacyMigrationFailure.changedStorage
                }
            }
        }
        let expected = Set(snapshot.entries.map { Data($0.path.utf8) })
        guard try listedPaths(root) == expected else { throw LegacyMigrationFailure.changedStorage }
    }

    func makeDirectory(_ root: Int32, components: [String]) throws -> Int32 {
        var current = dup(root)
        guard current >= 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        do {
            for name in components {
                guard name != ".", name != "..", !name.isEmpty, !name.contains("/"), !name.utf8.contains(0) else {
                    throw LegacyMigrationFailure.invalidRecord
                }
                if mkdirat(current, name, 0o700) != 0,
                   errno != EEXIST {
                    throw LegacyMigrationFailure.unavailable(errno)
                }
                let next = openat(current, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw LegacyMigrationFailure.unsafeStorage }
                Darwin.close(current); current = next
                try storage.validate(current, kind: S_IFDIR, mode: 0o700)
            }
            return current
        } catch { Darwin.close(current); throw error }
    }

    func write(_ bytes: Data, beneath root: Int32, components: [String], mode: mode_t = 0o600) throws {
        let parent = try openParent(root, components: Array(components.dropLast()))
        defer { Darwin.close(parent) }
        let descriptor = try openat(
            parent,
            last(components),
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode
        )
        guard descriptor >= 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        defer { Darwin.close(descriptor) }
        try storage.validate(descriptor, kind: S_IFREG, mode: mode)
        try storage.write(bytes, to: descriptor)
        try storage.syncFile(descriptor)
        guard fsync(parent) == 0 else { throw LegacyMigrationFailure.unavailable(errno) }
    }

    func readFile(beneath root: Int32, components: [String]) throws -> Data? {
        let parent = try openParent(root, components: Array(components.dropLast()))
        defer { Darwin.close(parent) }
        let descriptor = try openat(parent, last(components), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {
                return nil
            }
            throw LegacyMigrationFailure.unsafeStorage
        }
        defer { Darwin.close(descriptor) }
        try storage.validate(descriptor, kind: S_IFREG, mode: 0o600)
        return try read(descriptor)
    }

    func openParent(_ root: Int32, components: [String]) throws -> Int32 {
        var current = dup(root)
        guard current >= 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        do {
            for name in components {
                let next = openat(current, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw LegacyMigrationFailure.unsafeStorage }
                Darwin.close(current); current = next
                _ = try info(current, kind: S_IFDIR)
            }
            return current
        } catch { Darwin.close(current); throw error }
    }

    func syncDirectories(_ root: Int32) throws {
        for name in try names(root) {
            var raw = stat()
            guard fstatat(root, name, &raw, AT_SYMLINK_NOFOLLOW) == 0
            else { throw LegacyMigrationFailure.changedStorage }
            if raw.st_mode & S_IFMT == S_IFDIR {
                let child = try openParent(root, components: [name])
                defer { Darwin.close(child) }
                try syncDirectories(child)
            }
        }
        guard fsync(root) == 0 else { throw LegacyMigrationFailure.unavailable(errno) }
    }

    private func listedPaths(_ root: Int32, prefix: String = "") throws -> Set<Data> {
        var paths: Set<Data> = []
        for name in try names(root) {
            let path = prefix.isEmpty ? name : prefix + "/" + name
            guard paths.count < Self.maximumEntries else { throw LegacyMigrationFailure.invalidRecord }
            paths.insert(Data(path.utf8))
            var raw = stat()
            guard fstatat(root, name, &raw, AT_SYMLINK_NOFOLLOW) == 0
            else { throw LegacyMigrationFailure.changedStorage }
            if raw.st_mode & S_IFMT == S_IFDIR {
                let child = try openParent(root, components: [name]); defer { Darwin.close(child) }
                try paths.formUnion(listedPaths(child, prefix: path))
            }
        }
        return paths
    }
}
