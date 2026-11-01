import Darwin
import Foundation

/// Own this object on the listener's serialized executor. It is deliberately
/// not Sendable: descriptor release must not race later listener activation.
public final class CommandEndpointLease {
    public let location: CommandEndpointLocation
    private var runtime: Int32 = -1
    private var directory: Int32 = -1
    private var lock: Int32 = -1

    public init(location: CommandEndpointLocation) throws {
        self.location = location
        do {
            runtime = try Self.openDirectory(location.runtimeDirectory.path)
            try Self.requirePrivateDirectory(runtime)
            let leaf = location.directory.lastPathComponent
            if mkdirat(runtime, leaf, 0o700) != 0, errno != EEXIST {
                throw CommandEndpointError.unavailable(errno)
            }
            directory = openat(runtime, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directory >= 0 else { throw CommandEndpointError.insecureDirectory }
            try Self.requirePrivateDirectory(directory)
            lock = openat(directory, "lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
            guard lock >= 0 else { throw CommandEndpointError.insecureLock }
            try Self.requirePrivateLock(lock)
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
                if errno == EWOULDBLOCK {
                    throw CommandEndpointError.instanceBusy
                }
                throw CommandEndpointError.unavailable(errno)
            }
            try verifyOwnership()
        } catch {
            release()
            throw error
        }
    }

    deinit { release() }

    /// Never removes named filesystem objects, including a possibly live socket.
    public func release() {
        if lock >= 0 {
            Darwin.close(lock); lock = -1
        }
        if directory >= 0 {
            Darwin.close(directory); directory = -1
        }
        if runtime >= 0 {
            Darwin.close(runtime); runtime = -1
        }
    }

    public func verifyOwnership() throws {
        guard runtime >= 0, directory >= 0, lock >= 0 else { throw CommandEndpointError.identityChanged }
        let currentRuntime = try Self.openDirectory(location.runtimeDirectory.path)
        defer { Darwin.close(currentRuntime) }
        try Self.requirePrivateDirectory(currentRuntime)
        try Self.requirePrivateDirectory(directory)
        try Self.requirePrivateLock(lock)
        guard try Self.identity(currentRuntime) == Self.identity(runtime),
              try Self.namedIdentity(location.directory.lastPathComponent, in: runtime) == Self.identity(directory),
              try Self.namedIdentity("lock", in: directory) == Self.identity(lock) else {
            throw CommandEndpointError.identityChanged
        }
    }

    static func openDirectory(_ path: String) throws -> Int32 {
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw CommandEndpointError.unavailable(errno) }
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            let next = openat(current, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let failure = errno
            Darwin.close(current)
            guard next >= 0 else { throw CommandEndpointError.unavailable(failure) }
            current = next
        }
        return current
    }

    static func requirePrivateDirectory(_ descriptor: Int32) throws {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { throw CommandEndpointError.unavailable(errno) }
        guard attributes.st_mode & S_IFMT == S_IFDIR, attributes.st_uid == geteuid(),
              attributes.st_mode & 0o7777 == 0o700, try hasOnlyDenyACL(descriptor) else {
            throw CommandEndpointError.insecureDirectory
        }
        var filesystem = statfs()
        guard fstatfs(descriptor, &filesystem) == 0 else { throw CommandEndpointError.unavailable(errno) }
        guard filesystem.f_flags & UInt32(MNT_IGNORE_OWNERSHIP) == 0 else {
            throw CommandEndpointError.ownershipNotEnforced
        }
    }

    private static func requirePrivateLock(_ descriptor: Int32) throws {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { throw CommandEndpointError.unavailable(errno) }
        guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_uid == geteuid(),
              attributes.st_mode & 0o7777 == 0o600, attributes.st_nlink == 1,
              try hasOnlyDenyACL(descriptor) else { throw CommandEndpointError.insecureLock }
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static func identity(_ descriptor: Int32) throws -> Identity {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { throw CommandEndpointError.unavailable(errno) }
        return Identity(device: attributes.st_dev, inode: attributes.st_ino)
    }

    private static func namedIdentity(_ name: String, in parent: Int32) throws -> Identity {
        var attributes = stat()
        guard fstatat(parent, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw CommandEndpointError.identityChanged
        }
        return Identity(device: attributes.st_dev, inode: attributes.st_ino)
    }

    static func hasOnlyDenyACL(_ descriptor: Int32) throws -> Bool {
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOATTR || errno == ENOENT {
                return true
            }
            throw CommandEndpointError.unavailable(errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        return try hasOnlyDenyEntries(acl)
    }

    static func hasOnlyDenyEntries(_ acl: acl_t) throws -> Bool {
        guard acl_valid(acl) == 0 else { throw CommandEndpointError.unavailable(errno) }
        var entry: acl_entry_t?
        var selector: Int32 = 0 // Darwin ACL_FIRST_ENTRY.
        for _ in 0 ..< 1024 {
            if acl_get_entry(acl, selector, &entry) != 0 {
                guard errno == EINVAL else { throw CommandEndpointError.unavailable(errno) }
                return true
            }
            guard let entry else { throw CommandEndpointError.insecureDirectory }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else { throw CommandEndpointError.unavailable(errno) }
            if tag != ACL_EXTENDED_DENY {
                return false
            }
            selector = -1 // Darwin ACL_NEXT_ENTRY.
        }
        throw CommandEndpointError.insecureDirectory
    }
}

public enum CommandSocketPeer {
    /// Call on each accepted/connected Unix stream before processing protocol
    /// data. Kernel credentials identify a user, not a trusted application.
    public static func requireCurrentUser(_ descriptor: Int32) throws {
        var user: uid_t = 0
        var group: gid_t = 0
        var type: Int32 = 0
        var size = socklen_t(MemoryLayout.size(ofValue: type))
        guard getsockopt(descriptor, SOL_SOCKET, SO_TYPE, &type, &size) == 0, type == SOCK_STREAM,
              getpeereid(descriptor, &user, &group) == 0, user == geteuid() else {
            throw CommandEndpointError.invalidPeer
        }
    }
}
