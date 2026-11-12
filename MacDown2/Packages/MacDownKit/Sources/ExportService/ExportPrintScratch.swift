import Darwin
import Foundation

/// One AppKit print destination in a newly created private temporary directory.
/// The printer receives a pathname, but it never writes beside the user's
/// chosen export. Reads and retirement use the pinned directory descriptor.
public final class ExportPrintScratch: @unchecked Sendable {
    private typealias Filesystem = ExportPublicationFilesystem
    private static let leaf = "print.pdf"

    public let url: URL
    private let base: Filesystem.DirectoryHandle
    private let baseStamp: Filesystem.Stamp
    private let directoryName: String
    private let directory: Filesystem.DirectoryHandle
    private let directoryStamp: Filesystem.Stamp

    public convenience init() throws {
        try self.init(in: FileManager.default.temporaryDirectory)
    }

    /// A sandboxed app's per-container temporary directory may be advertised
    /// before it has been created. Materialize that OS-provided location before
    /// creating a private printer directory relative to its pinned descriptor.
    init(in base: URL) throws {
        try FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let baseDescriptor = Darwin.open(base.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard baseDescriptor >= 0 else {
            throw SetupError.posix(stage: "open temporary base", code: errno)
        }
        let pinnedBase = Filesystem.DirectoryHandle(baseDescriptor)
        guard let observedBase = try? Filesystem.directoryStamp(baseDescriptor) else {
            throw SetupError.unsafe(stage: "inspect temporary base")
        }
        guard observedBase.owner == geteuid(), observedBase.permissions & 0o077 == 0,
              (try? Filesystem.directoryAtPath(base.path, matches: observedBase)) == true
        else { throw SetupError.unsafe(stage: "validate temporary base") }

        let name = "mostlytext-print-\(UUID().uuidString)"
        guard mkdirat(baseDescriptor, name, 0o700) == 0 else {
            throw SetupError.posix(stage: "create print directory", code: errno)
        }
        let descriptor = openat(baseDescriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            let failure = SetupError.posix(stage: "open print directory", code: errno)
            _ = unlinkat(baseDescriptor, name, AT_REMOVEDIR)
            throw failure
        }
        let pinned = Filesystem.DirectoryHandle(descriptor)
        let path = base.appendingPathComponent(name).path
        do {
            guard let stamp = try? Filesystem.directoryStamp(descriptor) else {
                throw SetupError.unsafe(stage: "inspect print directory")
            }
            guard stamp.owner == geteuid(), stamp.permissions == 0o700,
                  (try? Filesystem.directoryAtPath(path, matches: stamp)) == true
            else { throw SetupError.unsafe(stage: "validate print directory") }
            self.base = pinnedBase
            baseStamp = observedBase
            directoryName = name
            directory = pinned
            directoryStamp = stamp
            url = URL(fileURLWithPath: path).appendingPathComponent(Self.leaf)
        } catch {
            _ = unlinkat(baseDescriptor, name, AT_REMOVEDIR)
            throw error
        }
    }

    /// A missing or empty printer result can trigger the memory-only snapshot
    /// fallback. A symlink, special file, changed directory or oversize result
    /// is refused before bytes enter PDFKit.
    public func read(maxBytes: Int) throws -> Data? {
        guard try Filesystem.directoryAtPath(url.deletingLastPathComponent().deletingLastPathComponent().path,
                                             matches: baseStamp),
            try Filesystem.childDirectory(directoryName, in: base.descriptor, matches: directoryStamp)
        else { throw ExportError.unsafePublication }
        return try Filesystem.readBoundedFile(Self.leaf, in: directory.descriptor, maxBytes: maxBytes)
    }

    /// Only the one regular printer leaf is retired. Unknown or substituted
    /// objects are left in the private directory for conservative recovery.
    public func retire() throws {
        guard try Filesystem.directoryAtPath(url.deletingLastPathComponent().deletingLastPathComponent().path,
                                             matches: baseStamp),
            try Filesystem.childDirectory(directoryName, in: base.descriptor, matches: directoryStamp)
        else { throw ExportError.unsafePublication }
        if let candidate = try Filesystem.primaryBaseline(Self.leaf, in: directory.descriptor) {
            guard candidate.owner == geteuid(), candidate.links == 1,
                  try Filesystem.childStamp(Self.leaf, in: directory.descriptor) == candidate
            else { throw ExportError.unsafePublication }
            guard unlinkat(directory.descriptor, Self.leaf, 0) == 0 else {
                throw Filesystem.posixFailure()
            }
        }
        guard unlinkat(base.descriptor, directoryName, AT_REMOVEDIR) == 0
        else { throw Filesystem.posixFailure() }
    }
}

/// Names the failing boundary without exposing a temporary pathname in the
/// user's Export alert. Hosted acceptance can distinguish setup failures from
/// later AppKit printing or final publication failures.
private enum SetupError: Error, LocalizedError {
    case posix(stage: String, code: Int32)
    case unsafe(stage: String)

    var errorDescription: String? {
        switch self {
        case let .posix(stage, code):
            "Preparing private PDF output failed at \(stage) (POSIX \(code))."
        case let .unsafe(stage):
            "Preparing private PDF output failed at \(stage) (directory identity changed)."
        }
    }
}
