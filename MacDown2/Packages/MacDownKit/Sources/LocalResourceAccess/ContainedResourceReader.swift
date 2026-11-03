import Darwin
import Foundation

/// Test seams that sit around the REAL syscalls so a test can replace filesystem objects at the exact moment a race
/// would matter. Production passes `.none`.
struct ResourceReadHooks: Sendable {
    var beforeOpen: (@Sendable () -> Void)?
    var afterOpen: (@Sendable () -> Void)?
    /// Called before each chunk read with the number of bytes read so far.
    var beforeChunk: (@Sendable (Int) -> Void)?

    static let none = ResourceReadHooks()
}

/// Reads one file beneath a pinned directory (or one pinned file) into immutable bytes. This is the blocking core: a
/// bounded I/O executor wraps it later, and this layer is where containment is decided. The security-bearing step is
/// the `openat` relative to the directory descriptor with `O_RESOLVE_BENEATH | O_NOFOLLOW_ANY`; the canonical
/// in-root symlink hint only chooses WHICH relative path to open and authorises nothing.
public enum ContainedResourceReader {
    static let openFlags = O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH
    static let chunkSize = 64 * 1024

    public static func read(
        _ reference: ResourceReference,
        in directory: DirectoryLease,
        maxBytes: Int,
        cancellation: ResourceCancellation = ResourceCancellation(),
        accounting: ResourceReadAccounting? = nil
    ) throws(ResourceReadError) -> ResourceSnapshot {
        try read(reference, in: directory, maxBytes: maxBytes, cancellation: cancellation, hooks: .none,
                 accounting: accounting)
    }

    static func read(
        _ reference: ResourceReference,
        in directory: DirectoryLease,
        maxBytes: Int,
        cancellation: ResourceCancellation,
        hooks: ResourceReadHooks,
        accounting: ResourceReadAccounting? = nil
    ) throws(ResourceReadError) -> ResourceSnapshot {
        guard !cancellation.isCancelled else { throw .cancelled }
        try accounting?.beginAttempt()
        guard directory.nameStillRefersToGrantedDirectory() else { throw .changedRoot }
        let relative = try constrainedRelativePath(for: reference, in: directory)
        return try readStrict(
            relativePath: relative,
            name: (relative as NSString).lastPathComponent,
            in: directory,
            limits: (maxBytes, cancellation),
            hooks: hooks, accounting: accounting
        )
    }

    /// The security-bearing step on its own: open `relativePath` beneath the pinned directory with the containment
    /// flags and read it. Nothing here consults the advisory hint, so tests (and any future caller) can hand it a
    /// hostile relative path and see the KERNEL refuse it.
    static func readStrict(
        relativePath: String,
        name: String,
        in directory: DirectoryLease,
        limits: (maxBytes: Int, cancellation: ResourceCancellation),
        hooks: ResourceReadHooks,
        accounting: ResourceReadAccounting? = nil
    ) throws(ResourceReadError) -> ResourceSnapshot {
        let (maxBytes, cancellation) = limits
        hooks.beforeOpen?()
        let result = try directory.owned.withDescriptor { rootDescriptor throws(ResourceReadError) in
            let descriptor = openat(rootDescriptor, relativePath, openFlags)
            guard descriptor >= 0 else { throw mapOpenError(errno) }
            defer { Darwin.close(descriptor) }
            hooks.afterOpen?()
            return try snapshot(
                descriptor: descriptor,
                name: name,
                maxBytes: maxBytes,
                cancellation: cancellation,
                hooks: hooks, accounting: accounting
            )
        }
        guard let result else { throw .leaseClosed }
        return result
    }

    /// Confirms at runtime that this kernel actually enforces the containment flags (a kernel that silently ignored
    /// `O_RESOLVE_BENEATH` / `O_NOFOLLOW_ANY` would otherwise go unnoticed): `..` must be refused and an in-root
    /// symlink must be refused. Throws `.unsupportedEnforcement` otherwise; callers must not fall back.
    public static func verifyEnforcement() throws(ResourceReadError) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("lra-probe-\(UUID().uuidString)")
        let root = base.appendingPathComponent("root")
        defer { try? FileManager.default.removeItem(at: base) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: root.appendingPathComponent("f"))
            try Data("y".utf8).write(to: base.appendingPathComponent("outside"))
            try FileManager.default.createSymbolicLink(
                atPath: root.appendingPathComponent("l").path,
                withDestinationPath: "f"
            )
        } catch {
            throw .unavailable(EIO)
        }
        let lease = try DirectoryLease(opening: root)
        defer { lease.close() }
        for (relative, expected) in [("../outside", ENOTCAPABLE), ("l", ELOOP)] {
            let descriptor = lease.owned.withDescriptor { openat($0, relative, openFlags) }
            if let descriptor, descriptor >= 0 {
                Darwin.close(descriptor)
                throw .unsupportedEnforcement
            }
            guard errno == expected else { throw .unsupportedEnforcement }
        }
    }

    /// Single-file grant: the lease IS the authority, no path is involved.
    public static func read(
        _ lease: FileLease,
        maxBytes: Int,
        cancellation: ResourceCancellation = ResourceCancellation()
    ) throws(ResourceReadError) -> ResourceSnapshot {
        try read(lease, maxBytes: maxBytes, cancellation: cancellation, hooks: .none)
    }

    static func read(
        _ lease: FileLease,
        maxBytes: Int,
        cancellation: ResourceCancellation,
        hooks: ResourceReadHooks
    ) throws(ResourceReadError) -> ResourceSnapshot {
        guard !cancellation.isCancelled else { throw .cancelled }
        let result = try lease.owned.withDescriptor { descriptor throws(ResourceReadError) in
            try snapshot(
                descriptor: descriptor,
                name: lease.name,
                maxBytes: maxBytes,
                cancellation: cancellation,
                hooks: hooks
            )
        }
        guard let result else { throw .leaseClosed }
        return result
    }

    // MARK: - Steps

    /// The in-root symlink hint: resolve the reference once against the granted directory's canonical path and require
    /// the result to remain beneath it, then return the path relative to the root. This is advisory — the strict
    /// `openat` below re-checks containment at open time.
    private static func constrainedRelativePath(
        for reference: ResourceReference,
        in directory: DirectoryLease
    ) throws(ResourceReadError) -> String {
        let candidate = directory.canonicalPath + "/" + reference.relativePath
        guard let resolved = realpath(candidate, nil) else { throw mapOpenError(errno) }
        defer { free(resolved) }
        let canonical = String(cString: resolved)
        // Compare UTF-8 bytes, not Characters: a combining mark right after the separator would otherwise fuse with
        // it into one grapheme and defeat the prefix test.
        let prefix =
            Array((directory.canonicalPath.hasSuffix("/") ? directory.canonicalPath : directory.canonicalPath + "/")
                    .utf8)
        let bytes = Array(canonical.utf8)
        guard bytes.count > prefix.count, bytes.starts(with: prefix),
              let relative = String(validating: bytes[prefix.count...], as: UTF8.self)
        else { throw .denied }
        return relative
    }

    private static func mapOpenError(_ code: Int32) -> ResourceReadError {
        switch code {
        case ELOOP, EACCES, EPERM, ENOTCAPABLE, EXDEV: .denied
        case EINVAL, ENOTSUP: .unsupportedEnforcement
        default: .unavailable(code)
        }
    }

    private static func snapshot(
        descriptor: Int32,
        name: String,
        maxBytes: Int,
        cancellation: ResourceCancellation,
        hooks: ResourceReadHooks,
        accounting: ResourceReadAccounting? = nil
    ) throws(ResourceReadError) -> ResourceSnapshot {
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw .unavailable(errno) }
        guard (before.st_mode & S_IFMT) == S_IFREG else { throw .nonRegular }
        guard before.st_size >= 0, Int64(before.st_size) <= Int64(maxBytes) else { throw .oversized }

        let bytes = try readAll(
            descriptor: descriptor,
            expectedSize: Int(before.st_size),
            maxBytes: maxBytes,
            cancellation: cancellation,
            hooks: hooks, accounting: accounting
        )

        var after = stat()
        guard fstat(descriptor, &after) == 0 else { throw .unavailable(errno) }
        guard unchanged(before, after, byteCount: bytes.count) else { throw .changedDuringRead }
        return ResourceSnapshot(
            bytes: bytes,
            identity: ResourceIdentity(after),
            name: name,
            mimeHint: MIMEHint.hint(forName: name)
        )
    }

    private static func readAll(
        descriptor: Int32,
        expectedSize: Int,
        maxBytes: Int,
        cancellation: ResourceCancellation,
        hooks: ResourceReadHooks,
        accounting: ResourceReadAccounting? = nil
    ) throws(ResourceReadError) -> Data {
        var bytes = Data()
        bytes.reserveCapacity(accounting?.readAllowance(upTo: expectedSize) ?? expectedSize)
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            guard !cancellation.isCancelled else { throw .cancelled }
            hooks.beforeChunk?(bytes.count)
            // Read at most one byte past the cap so growth beyond it is observable; never more than the buffer holds.
            // `remaining + 1` only runs when `remaining < chunkSize`, so it cannot overflow even for `maxBytes ==
            // Int.max`.
            let remaining = maxBytes - bytes.count
            let fileAllowance = remaining >= chunkSize ? chunkSize : remaining + 1
            let result: (bytesRead: Int, failure: Int32)
            if let accounting {
                result = try accounting.readChunk(upTo: fileAllowance) { want in
                    let count = Darwin.read(descriptor, &buffer, want)
                    return (count, errno)
                }
            } else {
                let count = Darwin.read(descriptor, &buffer, fileAllowance)
                result = (count, errno)
            }
            let (count, failure) = result
            if count < 0 {
                if failure == EINTR {
                    continue
                }
                throw .unavailable(failure)
            }
            if count == 0 {
                return bytes
            }
            let (total, overflow) = bytes.count.addingReportingOverflow(count)
            guard !overflow, total <= maxBytes else { throw .oversized }
            bytes.append(contentsOf: buffer[0 ..< count])
        }
    }

    private static func unchanged(_ before: stat, _ after: stat, byteCount: Int) -> Bool {
        ResourceIdentity(after) == ResourceIdentity(before)
            && after.st_size == before.st_size
            && after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec
            && after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec
            && Int64(byteCount) == Int64(after.st_size)
    }
}
