import Darwin
import Foundation

extension ThemeCatalogStore {
    /// The caller supplies a trusted physical parent and fixed namespace
    /// components. Imported theme names/IDs never become these path arguments.
    public nonisolated static func prepareManagedDirectory(
        beneath parent: URL, components: [String]
    ) throws -> ThemeCatalogStore {
        guard parent.isFileURL, parent.host == nil || parent.host == "", parent.user == nil, parent.password == nil,
              parent.query == nil, parent.fragment == nil, !components.isEmpty, components.count <= 8,
              components.allSatisfy(validDirectoryComponent) else { throw ThemeStorageError.invalidDirectory }
        var descriptor = open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY)
        guard descriptor >= 0 else { throw ThemeStorageError.invalidDirectory }
        defer { close(descriptor) }
        try checkBootstrapDirectory(descriptor)
        var location = parent
        for component in components {
            try Task.checkCancellation()
            if mkdirat(descriptor, component, 0o700) != 0, errno != EEXIST {
                throw ThemeStorageError.unavailable(errno)
            }
            let child = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            guard child >= 0 else { throw ThemeStorageError.invalidDirectory }
            do {
                try checkBootstrapDirectory(child)
            } catch {
                close(child)
                throw error
            }
            close(descriptor)
            descriptor = child
            location.appendPathComponent(component, isDirectory: true)
        }
        try Task.checkCancellation()
        let directory = try ThemeDirectory(url: location)
        var expected = stat()
        guard fstat(descriptor, &expected) == 0,
              directory.device == expected.st_dev, directory.inode == expected.st_ino else {
            throw ThemeStorageError.directoryChanged
        }
        return try ThemeCatalogStore(directory: directory)
    }

    private nonisolated static func validDirectoryComponent(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value != "." && value != ".."
            && !value.contains("/") && !value.utf8.contains(0)
    }

    private nonisolated static func checkBootstrapDirectory(_ descriptor: Int32) throws {
        var info = stat()
        var volume = statfs()
        guard fstat(descriptor, &info) == 0, fstatfs(descriptor, &volume) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(), info.st_mode & 0o022 == 0,
              volume.f_flags & UInt32(MNT_IGNORE_OWNERSHIP) == 0 else { throw ThemeStorageError.invalidDirectory }
    }
}
