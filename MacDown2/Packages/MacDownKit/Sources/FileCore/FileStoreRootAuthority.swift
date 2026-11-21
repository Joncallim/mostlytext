import Darwin
import Foundation

/// The physical folder chosen for a multi-file replacement. Publication uses
/// this retained descriptor and a relative name so moving a child directory
/// outside the folder cannot redirect the final write through an old handle.
public final class FileStoreRootAuthority: @unchecked Sendable {
    let descriptor: Int32
    let physicalRoot: URL
    private let lexicalComponents: [String]

    public init(root: URL) throws {
        guard root.isFileURL else { throw FileStoreError.invalidURL }
        lexicalComponents = root.standardizedFileURL.pathComponents
        // Foundation keeps /var as an alias on macOS. Resolve the complete
        // selected path before O_NOFOLLOW_ANY inspects every ancestor.
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(root.path, &resolved) != nil else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let physicalPath = FileManager.default.string(withFileSystemRepresentation: resolved,
                                                      length: Int(strlen(resolved)))
        physicalRoot = URL(fileURLWithPath: physicalPath, isDirectory: true)
        let opened = Darwin.open(physicalRoot.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY)
        guard opened >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        descriptor = opened
    }

    deinit { _ = Darwin.close(descriptor) }

    func relativePath(of destination: URL) throws -> String {
        guard destination.isFileURL else { throw FileStoreError.invalidURL }
        let components = destination.standardizedFileURL.pathComponents
        guard components.starts(with: lexicalComponents) else { throw FileStoreError.invalidURL }
        let relative = Array(components.dropFirst(lexicalComponents.count))
        guard !relative.isEmpty,
              relative.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\0") })
        else { throw FileStoreError.invalidURL }
        return relative.joined(separator: "/")
    }
}
