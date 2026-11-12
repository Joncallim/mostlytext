import Darwin
import Foundation

/// One AppKit print destination in a newly created private temporary directory.
/// The printer receives a pathname, but it never writes beside the user's
/// chosen export. Reads and retirement use the pinned directory descriptor.
public final class ExportPrintScratch: @unchecked Sendable {
    private typealias Filesystem = ExportPublicationFilesystem
    private static let leaf = "print.pdf"

    public let url: URL
    private let directory: Filesystem.DirectoryHandle
    private let directoryStamp: Filesystem.Stamp

    public init() throws {
        let base = FileManager.default.temporaryDirectory
        var template = Array(base.appendingPathComponent("mostlytext-print-XXXXXX").path.utf8CString)
        guard let created = mkdtemp(&template) else { throw Filesystem.posixFailure() }
        let path = String(cString: created)
        let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            _ = rmdir(path)
            throw Filesystem.posixFailure()
        }
        let pinned = Filesystem.DirectoryHandle(descriptor)
        do {
            let stamp = try Filesystem.directoryStamp(descriptor)
            guard stamp.owner == geteuid(), stamp.permissions == 0o700,
                  try Filesystem.directoryAtPath(path, matches: stamp)
            else { throw ExportError.unsafePublication }
            directory = pinned
            directoryStamp = stamp
            url = URL(fileURLWithPath: path).appendingPathComponent(Self.leaf)
        } catch {
            _ = rmdir(path)
            throw error
        }
    }

    /// A missing or empty printer result can trigger the memory-only snapshot
    /// fallback. A symlink, special file, changed directory or oversize result
    /// is refused before bytes enter PDFKit.
    public func read(maxBytes: Int) throws -> Data? {
        guard try Filesystem.directoryAtPath(url.deletingLastPathComponent().path, matches: directoryStamp)
        else { throw ExportError.unsafePublication }
        return try Filesystem.readBoundedFile(Self.leaf, in: directory.descriptor, maxBytes: maxBytes)
    }

    /// Only the one regular printer leaf is retired. Unknown or substituted
    /// objects are left in the private directory for conservative recovery.
    public func retire() throws {
        let path = url.deletingLastPathComponent().path
        guard try Filesystem.directoryAtPath(path, matches: directoryStamp)
        else { throw ExportError.unsafePublication }
        if let candidate = try Filesystem.primaryBaseline(Self.leaf, in: directory.descriptor) {
            guard candidate.owner == geteuid(), candidate.links == 1,
                  try Filesystem.childStamp(Self.leaf, in: directory.descriptor) == candidate
            else { throw ExportError.unsafePublication }
            guard unlinkat(directory.descriptor, Self.leaf, 0) == 0 else {
                throw Filesystem.posixFailure()
            }
        }
        guard rmdir(path) == 0 else { throw Filesystem.posixFailure() }
    }
}
