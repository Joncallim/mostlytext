import Darwin
import Foundation

extension MigrationJournalDirectory {
    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    func identity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    func namedIdentity(_ name: String) throws -> Identity {
        var info = stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw LegacyMigrationFailure.changedStorage
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    func validate(_ descriptor: Int32, kind: mode_t, mode: mode_t) throws {
        var info = stat()
        var filesystem = statfs()
        guard fstat(descriptor, &info) == 0, fstatfs(descriptor, &filesystem) == 0,
              info.st_mode & S_IFMT == kind, info.st_mode & 0o7777 == mode,
              info.st_uid == geteuid(), kind == S_IFDIR || info.st_nlink == 1,
              filesystem.f_flags & UInt32(MNT_IGNORE_OWNERSHIP) == 0 else {
            throw LegacyMigrationFailure.unsafeStorage
        }
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOATTR || errno == ENOENT {
                return
            }
            throw LegacyMigrationFailure.unavailable(errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw LegacyMigrationFailure.unsafeStorage }
        var entry: acl_entry_t?
        var selector: Int32 = 0
        for _ in 0 ..< 1024 {
            if acl_get_entry(acl, selector, &entry) != 0 {
                guard errno == EINVAL else { throw LegacyMigrationFailure.unsafeStorage }
                return
            }
            guard let entry else { throw LegacyMigrationFailure.unsafeStorage }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0, tag == ACL_EXTENDED_DENY else {
                throw LegacyMigrationFailure.unsafeStorage
            }
            selector = -1
        }
        throw LegacyMigrationFailure.unsafeStorage
    }
}
