import Darwin
import Foundation

/// Builds a private copy directly beneath the selected root, then resolves
/// the final destination from that root in one no-following rename. A child
/// directory moved outside the root during copying cannot redirect the write.
enum FileTreeRootedCopy {
    static func copy(
        _ source: URL, to destination: URL, root: FileTreeRootedDirectory,
        beforePublication: (@Sendable () throws -> Void)? = nil
    ) throws {
        let destinationPath = try root.relativePath(of: destination)
        try root.withReadableParent(of: source) { sourceParent, sourceName in
            let stage = ".mostlytext-copy-\(UUID().uuidString)"
            var created = false
            do {
                try sourceName.withCString { sourcePointer in
                    try stage.withCString { stagePointer in
                        try copyNode(
                            sourceParent, sourcePointer, root.descriptor, stagePointer,
                            created: &created
                        )
                    }
                }
                try beforePublication?()
                guard Darwin.renameatx_np(
                    root.descriptor, stage, root.descriptor, destinationPath,
                    UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY)
                ) == 0 else { throw FileTreeRootedDirectory.failure() }
            } catch {
                if created {
                    try stage.withCString { try removeNode(root.descriptor, $0) }
                }
                throw error
            }
        }
    }

    private static func copyNode(
        _ sourceParent: Int32, _ sourceName: UnsafePointer<CChar>,
        _ destinationParent: Int32, _ destinationName: UnsafePointer<CChar>,
        created: inout Bool
    ) throws {
        var info = stat()
        guard Darwin.fstatat(sourceParent, sourceName, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw FileTreeRootedDirectory.failure()
        }
        switch info.st_mode & S_IFMT {
        case S_IFREG:
            try copyRegularFile(sourceParent, sourceName, destinationParent, destinationName, created: &created)
        case S_IFDIR:
            try copyDirectory(sourceParent, sourceName, destinationParent, destinationName, created: &created)
        case S_IFLNK:
            try copySymbolicLink(sourceParent, sourceName, destinationParent, destinationName, created: &created)
        default:
            throw POSIXError(.ENOTSUP)
        }
    }

    private static func copyRegularFile(
        _ sourceParent: Int32, _ sourceName: UnsafePointer<CChar>,
        _ destinationParent: Int32, _ destinationName: UnsafePointer<CChar>,
        created: inout Bool
    ) throws {
        let source = Darwin.openat(sourceParent, sourceName, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard source >= 0 else { throw FileTreeRootedDirectory.failure() }
        defer { _ = Darwin.close(source) }
        let destination = Darwin.openat(
            destinationParent, destinationName, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600
        )
        guard destination >= 0 else { throw FileTreeRootedDirectory.failure() }
        created = true
        defer { _ = Darwin.close(destination) }
        guard Darwin.fcopyfile(source, destination, nil, copyfile_flags_t(COPYFILE_ALL)) == 0 else {
            throw FileTreeRootedDirectory.failure()
        }
    }

    private static func copyDirectory(
        _ sourceParent: Int32, _ sourceName: UnsafePointer<CChar>,
        _ destinationParent: Int32, _ destinationName: UnsafePointer<CChar>,
        created: inout Bool
    ) throws {
        let source = Darwin.openat(sourceParent, sourceName, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard source >= 0 else { throw FileTreeRootedDirectory.failure() }
        defer { _ = Darwin.close(source) }
        guard Darwin.mkdirat(destinationParent, destinationName, 0o700) == 0 else {
            throw FileTreeRootedDirectory.failure()
        }
        created = true
        let destination = Darwin.openat(
            destinationParent, destinationName, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard destination >= 0 else { throw FileTreeRootedDirectory.failure() }
        defer { _ = Darwin.close(destination) }
        try visitChildren(source) { name in
            var childCreated = false
            try copyNode(source, name, destination, name, created: &childCreated)
        }
        guard Darwin.fcopyfile(source, destination, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
            throw FileTreeRootedDirectory.failure()
        }
    }

    private static func copySymbolicLink(
        _ sourceParent: Int32, _ sourceName: UnsafePointer<CChar>,
        _ destinationParent: Int32, _ destinationName: UnsafePointer<CChar>,
        created: inout Bool
    ) throws {
        var target = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let length = target.withUnsafeMutableBufferPointer { buffer in
            Darwin.readlinkat(sourceParent, sourceName, buffer.baseAddress, buffer.count - 1)
        }
        guard length >= 0, length < target.count - 1 else { throw FileTreeRootedDirectory.failure() }
        target[length] = 0
        let result = target.withUnsafeBufferPointer { buffer in
            Darwin.symlinkat(buffer.baseAddress, destinationParent, destinationName)
        }
        guard result == 0 else { throw FileTreeRootedDirectory.failure() }
        created = true
    }

    private static func removeNode(_ parent: Int32, _ name: UnsafePointer<CChar>) throws {
        var info = stat()
        guard Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw FileTreeRootedDirectory.failure()
        }
        if info.st_mode & S_IFMT == S_IFDIR {
            let directory = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            guard directory >= 0 else { throw FileTreeRootedDirectory.failure() }
            defer { _ = Darwin.close(directory) }
            // Copied source permissions may remove write access. Restore it on
            // this private stage before removing children after a failed copy.
            guard Darwin.fchmod(directory, 0o700) == 0 else { throw FileTreeRootedDirectory.failure() }
            try visitChildren(directory) { child in try removeNode(directory, child) }
            guard Darwin.unlinkat(parent, name, AT_REMOVEDIR) == 0 else {
                throw FileTreeRootedDirectory.failure()
            }
        } else {
            guard Darwin.unlinkat(parent, name, 0) == 0 else { throw FileTreeRootedDirectory.failure() }
        }
    }

    private static func visitChildren(
        _ descriptor: Int32, _ body: (UnsafePointer<CChar>) throws -> Void
    ) throws {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else { throw FileTreeRootedDirectory.failure() }
        guard let stream = Darwin.fdopendir(duplicate) else {
            _ = Darwin.close(duplicate)
            throw FileTreeRootedDirectory.failure()
        }
        defer { _ = Darwin.closedir(stream) }
        while true {
            errno = 0
            guard let entry = Darwin.readdir(stream) else {
                guard errno == 0 else { throw FileTreeRootedDirectory.failure() }
                return
            }
            try withUnsafePointer(to: &entry.pointee.d_name) { field in
                let name = UnsafeRawPointer(field).assumingMemoryBound(to: CChar.self)
                if Darwin.strcmp(name, ".") != 0, Darwin.strcmp(name, "..") != 0 {
                    try body(name)
                }
            }
        }
    }
}
