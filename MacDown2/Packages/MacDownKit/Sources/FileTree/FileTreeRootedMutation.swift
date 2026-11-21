import Darwin
import Foundation

/// Opens the originally selected physical folder once, then resolves each
/// mutation parent from that descriptor without following directory links.
/// The caller's lexical URL is used only to derive a root-relative name.
final class FileTreeRootedDirectory {
    let descriptor: Int32
    let lexicalComponents: [String]

    init(_ authority: FileTreeMutationAuthority) throws {
        lexicalComponents = authority.lexicalRoot.standardizedFileURL.pathComponents
        // Foundation's resolved URL can retain an ancestor alias (for example
        // macOS /var). The descriptor's device/inode comparison is the root
        // authority; child traversal below refuses directory links.
        let opened = Darwin.open(authority.physicalRoot.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard opened >= 0 else { throw Self.failure() }
        var info = stat()
        guard Darwin.fstat(opened, &info) == 0,
              info.st_dev == authority.identity.device,
              info.st_ino == authority.identity.inode,
              FileTreeRootIdentity(url: authority.lexicalRoot) == authority.identity else {
            _ = Darwin.close(opened)
            throw FileTreeOperationError.outsideCurrentRoot
        }
        descriptor = opened
    }

    deinit { _ = Darwin.close(descriptor) }

    func withParent<T>(of url: URL, _ body: (Int32, String) throws -> T) throws -> T {
        let components = url.standardizedFileURL.pathComponents
        guard components.starts(with: lexicalComponents) else {
            throw FileTreeOperationError.outsideCurrentRoot
        }
        let relative = Array(components.dropFirst(lexicalComponents.count))
        guard let name = relative.last, !name.isEmpty,
              relative.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("/") }) else {
            throw FileTreeOperationError.outsideCurrentRoot
        }
        var parent = Darwin.dup(descriptor)
        guard parent >= 0 else { throw Self.failure() }
        defer { _ = Darwin.close(parent) }
        for component in relative.dropLast() {
            let next = Darwin.openat(
                parent, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
            guard next >= 0 else { throw Self.failure() }
            _ = Darwin.close(parent)
            parent = next
        }
        return try body(parent, name)
    }

    func withReadableParent<T>(of url: URL, _ body: (Int32, String) throws -> T) throws -> T {
        if url.standardizedFileURL.pathComponents.starts(with: lexicalComponents) {
            return try withParent(of: url, body)
        }
        // Finder may supply an external source. Only its destination is a
        // write authority; opening this parent by path is a read operation.
        let parent = Darwin.open(
            url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC
        )
        guard parent >= 0 else { throw Self.failure() }
        defer { _ = Darwin.close(parent) }
        return try body(parent, url.lastPathComponent)
    }

    static func failure() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

public extension FileSystemMutator {
    func mutate(_ operation: FileTreeMutation, authority: FileTreeMutationAuthority) async throws {
        try await Task.detached {
            let root = try FileTreeRootedDirectory(authority)
            switch operation {
            case let .createFile(url):
                try root.withParent(of: url) { parent, name in
                    try beforeRootedMutation?()
                    let file = Darwin.openat(
                        parent, name, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW, 0o666
                    )
                    guard file >= 0 else { throw FileTreeRootedDirectory.failure() }
                    _ = Darwin.close(file)
                }
            case let .createDirectory(url):
                try root.withParent(of: url) { parent, name in
                    try beforeRootedMutation?()
                    guard Darwin.mkdirat(parent, name, 0o777) == 0 else {
                        throw FileTreeRootedDirectory.failure()
                    }
                }
            case let .move(source, destination):
                try root.withParent(of: source) { sourceParent, sourceName in
                    try root.withParent(of: destination) { destinationParent, destinationName in
                        try beforeRootedMutation?()
                        guard Darwin.renameatx_np(
                            sourceParent, sourceName, destinationParent, destinationName, UInt32(RENAME_EXCL)
                        ) == 0 else { throw FileTreeRootedDirectory.failure() }
                    }
                }
            case let .copy(source, destination):
                try FileTreeRootedCopy.copy(source, to: destination, root: root,
                                            beforePublication: beforeRootedMutation)
            case let .trash(url):
                try await trash(at: url)
            }
        }.value
    }
}
