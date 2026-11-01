import Darwin
import Foundation

struct CommandSocketIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let birthSeconds: Int
    let birthNanoseconds: Int

    init(_ attributes: stat) {
        device = attributes.st_dev
        inode = attributes.st_ino
        birthSeconds = attributes.st_birthtimespec.tv_sec
        birthNanoseconds = attributes.st_birthtimespec.tv_nsec
    }
}

/// A read-only namespace handle for clients and the lease-owning listener.
/// It never creates, locks or removes a directory or lock file.
final class CommandEndpointNamespace {
    let location: CommandEndpointLocation
    private var runtime: Int32 = -1
    private var directory: Int32 = -1

    init(_ location: CommandEndpointLocation) throws {
        self.location = location
        do {
            runtime = try CommandEndpointLease.openDirectory(location.runtimeDirectory.path)
            try CommandEndpointLease.requirePrivateDirectory(runtime)
            directory = openat(runtime, location.directory.lastPathComponent,
                               O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directory >= 0 else { throw CommandEndpointError.unavailable(errno) }
            try verify()
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    private func close() {
        if directory >= 0 {
            Darwin.close(directory); directory = -1
        }
        if runtime >= 0 {
            Darwin.close(runtime); runtime = -1
        }
    }

    func verify() throws {
        let current = try CommandEndpointLease.openDirectory(location.runtimeDirectory.path)
        defer { Darwin.close(current) }
        try CommandEndpointLease.requirePrivateDirectory(current)
        try CommandEndpointLease.requirePrivateDirectory(directory)
        var opened = stat()
        var held = stat()
        var named = stat()
        var endpoint = stat()
        guard fstat(current, &opened) == 0, fstat(runtime, &held) == 0,
              fstatat(runtime, location.directory.lastPathComponent, &named, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(directory, &endpoint) == 0,
              opened.st_dev == held.st_dev, opened.st_ino == held.st_ino,
              named.st_dev == endpoint.st_dev, named.st_ino == endpoint.st_ino else {
            throw CommandEndpointError.identityChanged
        }
    }

    func socketIdentity(requirePrivateMode: Bool = true) throws -> CommandSocketIdentity? {
        try verify()
        guard let attributes = try attributes("s") else { return nil }
        guard attributes.st_mode & S_IFMT == S_IFSOCK, attributes.st_uid == geteuid(),
              attributes.st_nlink == 1 else { throw CommandEndpointError.insecureSocket }
        if requirePrivateMode {
            guard attributes.st_mode & 0o7777 == 0o600, try socketHasOnlyDenyACL() else {
                throw CommandEndpointError.insecureSocket
            }
        }
        try verify()
        guard let after = try self.attributes("s"),
              CommandSocketIdentity(after) == CommandSocketIdentity(attributes) else {
            throw CommandEndpointError.identityChanged
        }
        return CommandSocketIdentity(attributes)
    }

    func secureSocket(expected: CommandSocketIdentity) throws {
        guard try socketIdentity(requirePrivateMode: false) == expected else {
            throw CommandEndpointError.identityChanged
        }
        guard fchmodat(directory, "s", 0o600, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw CommandEndpointError.unavailable(errno)
        }
        guard try socketIdentity() == expected else { throw CommandEndpointError.identityChanged }
    }

    /// Caller must own and revalidate the exclusive instance lease. Quarantine
    /// first so a replaced path cannot make cleanup delete an unknown object.
    func retireSocket(expected: CommandSocketIdentity, beforeMove: (() throws -> Void)? = nil) throws {
        guard try socketIdentity(requirePrivateMode: false) == expected else {
            throw CommandEndpointError.identityChanged
        }
        let quarantine = "retired-" + UUID().uuidString
        // Internal deterministic race control; production supplies no hook.
        try beforeMove?()
        guard renameatx_np(directory, "s", directory, quarantine, UInt32(RENAME_EXCL)) == 0 else {
            throw CommandEndpointError.unavailable(errno)
        }
        do {
            guard let moved = try attributes(quarantine), CommandSocketIdentity(moved) == expected,
                  moved.st_mode & S_IFMT == S_IFSOCK, moved.st_uid == geteuid(), moved.st_nlink == 1 else {
                throw CommandEndpointError.identityChanged
            }
            guard unlinkat(directory, quarantine, 0) == 0 else { throw CommandEndpointError.unavailable(errno) }
        } catch {
            // RENAME_EXCL preserves a newer path. If restoration cannot happen,
            // leave the displaced object under its private quarantine name.
            _ = renameatx_np(directory, quarantine, directory, "s", UInt32(RENAME_EXCL))
            throw error
        }
    }

    private func attributes(_ leaf: String) throws -> stat? {
        var attributes = stat()
        if fstatat(directory, leaf, &attributes, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT {
                return nil
            }
            throw CommandEndpointError.unavailable(errno)
        }
        return attributes
    }

    private func socketHasOnlyDenyACL() throws -> Bool {
        guard let acl = acl_get_link_np(location.socketPath, ACL_TYPE_EXTENDED) else {
            if errno == ENOATTR || errno == ENOENT {
                return true
            }
            throw CommandEndpointError.unavailable(errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        return try CommandEndpointLease.hasOnlyDenyEntries(acl)
    }
}
