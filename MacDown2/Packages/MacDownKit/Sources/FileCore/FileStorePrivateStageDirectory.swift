import Darwin
import Foundation

/// Keeps a save stage inaccessible on volumes that enforce POSIX permissions
/// while its bytes and destination metadata are prepared. The directory is on
/// the destination volume, so publication remains a same-volume rename or exchange.
final class FileStorePrivateStageDirectory {
    let url: URL
    let parent: Int32
    let directory: Int32
    private let name: String
    private let identity: stat

    init(for destination: URL) throws {
        let parentURL = destination.deletingLastPathComponent()
        let parentFD = open(parentURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parentFD >= 0 else { throw Self.posixFailure() }
        var retainParent = false
        defer {
            if !retainParent {
                _ = Darwin.close(parentFD)
            }
        }
        let entryName = FileStore.companionName(for: destination, infix: "private-stage")
        guard mkdirat(parentFD, entryName, 0o700) == 0 else { throw Self.posixFailure() }

        let directory = openat(parentFD, entryName, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directory >= 0 else { throw Self.posixFailure() }
        var retainDirectory = false
        defer {
            if !retainDirectory {
                var opened = stat()
                var named = stat()
                if fstat(directory, &opened) == 0,
                   fstatat(parentFD, entryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
                   FileStoreRetirement.sameObject(opened, named) {
                    _ = unlinkat(parentFD, entryName, AT_REMOVEDIR)
                }
                _ = Darwin.close(directory)
            }
        }

        // A parent ACL can be inherited even when mkdir requests mode 0700.
        // Clear it before placing any authored bytes inside this directory.
        let emptyACL = acl_init(0)
        guard let emptyACL else { throw Self.posixFailure() }
        defer { _ = acl_free(UnsafeMutableRawPointer(emptyACL)) }
        if acl_set_fd_np(directory, emptyACL, ACL_TYPE_EXTENDED) != 0,
           errno != ENOTSUP, errno != ENOATTR {
            throw Self.posixFailure()
        }

        var opened = stat()
        var named = stat()
        guard fstat(directory, &opened) == 0,
              fstatat(parentFD, entryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              FileStoreRetirement.sameObject(opened, named),
              opened.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
        else {
            throw POSIXError(.EACCES)
        }
        parent = parentFD
        self.directory = directory
        name = entryName
        url = parentURL.appendingPathComponent(entryName, isDirectory: true)
        identity = opened
        retainParent = true
        retainDirectory = true
    }

    deinit {
        _ = Darwin.close(directory)
        _ = Darwin.close(parent)
    }

    func isStillNamed() -> Bool {
        var named = stat()
        return fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0
            && FileStoreRetirement.sameObject(named, identity)
            && named.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    }

    /// Check the original directory identity before attempting empty-directory
    /// removal. A retained recovery stage prevents removal. This check does
    /// not make the final path-based unlink immune to a hostile parent rename.
    func removeIfEmpty() {
        var named = stat()
        guard fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              FileStoreRetirement.sameObject(named, identity),
              named.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
        else { return }
        _ = unlinkat(parent, name, AT_REMOVEDIR)
    }

    private static func posixFailure() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
