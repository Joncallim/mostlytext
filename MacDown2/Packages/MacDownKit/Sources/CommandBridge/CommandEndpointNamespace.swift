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

/// An anchored namespace handle for clients and the lease-owning listener.
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

    func socketIdentity(requirePrivateMode: Bool = true, leaf: String = "s") throws -> CommandSocketIdentity? {
        try verify()
        guard let attributes = try attributes(leaf) else { return nil }
        guard attributes.st_mode & S_IFMT == S_IFSOCK, attributes.st_uid == geteuid(),
              attributes.st_nlink == 1 else { throw CommandEndpointError.insecureSocket }
        if requirePrivateMode {
            guard attributes.st_mode & 0o7777 == 0o600, try socketHasOnlyDenyACL(leaf) else {
                throw CommandEndpointError.insecureSocket
            }
        }
        try verify()
        guard let after = try self.attributes(leaf),
              CommandSocketIdentity(after) == CommandSocketIdentity(attributes) else {
            throw CommandEndpointError.identityChanged
        }
        return CommandSocketIdentity(attributes)
    }

    func secureSocket(expected: CommandSocketIdentity, leaf: String = "s") throws {
        guard try socketIdentity(requirePrivateMode: false, leaf: leaf) == expected else {
            throw CommandEndpointError.identityChanged
        }
        guard fchmodat(directory, leaf, 0o600, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw CommandEndpointError.unavailable(errno)
        }
        guard try socketIdentity(leaf: leaf) == expected else { throw CommandEndpointError.identityChanged }
    }

    /// Caller must own and revalidate the exclusive instance lease. Quarantine
    /// first so a replaced path cannot make cleanup delete an unknown object.
    func retireSocket(
        expected: CommandSocketIdentity,
        leaf: String = "s",
        beforeMove: (() throws -> Void)? = nil
    ) throws {
        guard try socketIdentity(requirePrivateMode: false, leaf: leaf) == expected else {
            throw CommandEndpointError.identityChanged
        }
        let quarantine = "retired-" + UUID().uuidString
        // Internal deterministic race control; production supplies no hook.
        try beforeMove?()
        guard renameatx_np(directory, leaf, directory, quarantine, UInt32(RENAME_EXCL)) == 0 else {
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
            _ = renameatx_np(directory, quarantine, directory, leaf, UInt32(RENAME_EXCL))
            throw error
        }
    }

    /// Bound sockets stay under a private unpublished leaf until both mode
    /// and listen state are ready. No process-global umask change is needed.
    func bindStagedSocket(_ descriptor: Int32, until deadline: ContinuousClock.Instant,
                          isCancelled: @Sendable () -> Bool) throws -> (String, CommandSocketIdentity) {
        let room = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 2 - location.directory.path.utf8.count
        guard room >= 1 else { throw CommandEndpointError.invalidLocation }
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        let offset = Int.random(in: 0 ..< alphabet.count)
        for attempt in 0 ..< alphabet.count {
            let prefix = String(alphabet[(offset + attempt) % alphabet.count])
            let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(min(room, 16) - 1)
            let leaf = prefix + suffix
            if leaf.lowercased() == "s" || leaf.lowercased() == "lock" {
                continue
            }
            try verify()
            try CommandSocketPolling.check(descriptor, deadline: deadline, cancelled: isCancelled)
            let result = try CommandSocketPolling.withAddress(location.directory.appendingPathComponent(leaf).path) {
                Darwin.bind(descriptor, $0, $1)
            }
            if result != 0 {
                let code = errno
                if code == EADDRINUSE || code == EEXIST {
                    continue
                }
                throw CommandSocketError.unavailable(code)
            }
            guard let identity = try socketIdentity(requirePrivateMode: false, leaf: leaf) else {
                throw CommandEndpointError.identityChanged
            }
            return (leaf, identity)
        }
        throw CommandSocketError.unavailable(EADDRINUSE)
    }

    func publishSocket(from leaf: String, expected: CommandSocketIdentity) throws {
        guard try socketIdentity(leaf: leaf) == expected else { throw CommandEndpointError.identityChanged }
        guard renameatx_np(directory, leaf, directory, "s", UInt32(RENAME_EXCL)) == 0 else {
            throw CommandEndpointError.unavailable(errno)
        }
        guard try socketIdentity() == expected else { throw CommandEndpointError.identityChanged }
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

    private func socketHasOnlyDenyACL(_ leaf: String) throws -> Bool {
        guard let acl = acl_get_link_np(location.directory.appendingPathComponent(leaf).path, ACL_TYPE_EXTENDED) else {
            if errno == ENOATTR || errno == ENOENT {
                return true
            }
            throw CommandEndpointError.unavailable(errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        return try CommandEndpointLease.hasOnlyDenyEntries(acl)
    }
}
