import Darwin
import Foundation

/// Bounded no-follow helpers for the managed companion transaction only.
enum ExportCompanionFiles {
    typealias Filesystem = ExportPublicationFilesystem

    static func stamp(_ name: String, in directory: Int32) throws -> Filesystem.Stamp? {
        var value = stat()
        if fstatat(directory, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT {
                return nil
            }
            throw Filesystem.posixFailure()
        }
        return Filesystem.Stamp(value)
    }

    static func create(
        _ name: String, in directory: Int32,
        bytes: (Filesystem.Stamp) throws -> Data,
        afterCreation: ((Filesystem.Stamp) throws -> Void)? = nil
    ) throws -> ExportOwnedFileReceipt {
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Filesystem.posixFailure() }
        defer { Darwin.close(descriptor) }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0 else { throw Filesystem.posixFailure() }
        let identity = Filesystem.Stamp(initial)
        guard identity.kind == mode_t(S_IFREG), identity.owner == geteuid(), identity.links == 1,
              identity.permissions == 0o600 else { throw ExportError.unsafePublication }
        try afterCreation?(identity)
        let bytes = try bytes(identity)
        guard bytes.count <= ExportResourceBudget.standard.maxSingleResourceBytes
        else { throw ExportError.unsafePublication }
        // Any write/receipt gap remains preserved and blocks further growth.
        // A planned name alone never permits deleting a partial stage.
        var progress = 0
        try Filesystem.writeAll(bytes, to: descriptor, progress: &progress)
        guard fsync(descriptor) == 0, fsync(directory) == 0 else { throw Filesystem.posixFailure() }
        var final = stat()
        guard fstat(descriptor, &final) == 0,
              ExportCompanionObjectIdentity(identity).sameFile(as: Filesystem.Stamp(final)),
              try stamp(name, in: directory) == Filesystem.Stamp(final)
        else { throw ExportError.unsafePublication }
        return try ExportOwnedFileReceipt(bytes: bytes, stamp: Filesystem.Stamp(final))
    }
}
