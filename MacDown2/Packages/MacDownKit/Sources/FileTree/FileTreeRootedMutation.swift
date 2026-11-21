import Darwin
import Foundation

/// Opens the originally selected physical folder once. Final create, move and
/// copy publication resolves both names from that root in one operation that
/// refuses directory links. A child directory moved outside the root cannot
/// redirect the final mutation through a previously opened child descriptor.
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

    private func relativeComponents(of url: URL) throws -> [String] {
        let components = url.standardizedFileURL.pathComponents
        guard components.starts(with: lexicalComponents) else {
            throw FileTreeOperationError.outsideCurrentRoot
        }
        let relative = Array(components.dropFirst(lexicalComponents.count))
        guard let name = relative.last, !name.isEmpty,
              relative.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\0") }) else {
            throw FileTreeOperationError.outsideCurrentRoot
        }
        return relative
    }

    func relativePath(of url: URL) throws -> String {
        try relativeComponents(of: url).joined(separator: "/")
    }

    func withParent<T>(of url: URL, _ body: (Int32, String) throws -> T) throws -> T {
        let relative = try relativeComponents(of: url)
        let name = relative[relative.count - 1]
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

    func requireExclusiveRename(at destination: URL) throws {
        // An in-root mount can use a different filesystem from the selected
        // root. The destination's parent determines whether exclusive rename
        // is supported; a root-stage rename across volumes still fails.
        try withParent(of: destination) { parent, _ in
            var attributes = attrlist()
            attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
            attributes.volattr = UInt32(ATTR_VOL_CAPABILITIES)
            var reply = (length: UInt32(0), capabilities: vol_capabilities_attr_t())
            let size = MemoryLayout.size(ofValue: reply)
            let result = withUnsafeMutablePointer(to: &reply) { buffer in
                Darwin.fgetattrlist(parent, &attributes, buffer, size, 0)
            }
            let flag = UInt32(VOL_CAP_INT_RENAME_EXCL)
            guard result == 0, reply.length >= UInt32(size),
                  reply.capabilities.valid.1 & flag != 0,
                  reply.capabilities.capabilities.1 & flag != 0
            else { throw POSIXError(.ENOTSUP) }
        }
    }

    func createFile(at url: URL, beforePublication: (() throws -> Void)?) throws {
        let destination = try relativePath(of: url)
        try beforePublication?()
        let file = Darwin.openat(
            descriptor, destination, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW_ANY, 0o666
        )
        guard file >= 0 else { throw Self.failure() }
        _ = Darwin.close(file)
    }

    func createDirectory(at url: URL, beforePublication: (() throws -> Void)?) throws {
        let destination = try relativePath(of: url)
        try requireExclusiveRename(at: url)
        // mkdirat has no no-follow-any option. Stage under the selected root,
        // then resolve the destination from that root in one exclusive rename.
        // A nested mount on another volume fails closed at rename.
        let stage = ".mostlytext-create-\(UUID().uuidString)"
        guard Darwin.mkdirat(descriptor, stage, 0o777) == 0 else { throw Self.failure() }
        do {
            try beforePublication?()
            guard Darwin.renameatx_np(
                descriptor, stage, descriptor, destination,
                UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY)
            ) == 0 else { throw Self.failure() }
        } catch {
            _ = Darwin.unlinkat(descriptor, stage, AT_REMOVEDIR)
            throw error
        }
    }

    func move(_ source: URL, to destination: URL, beforePublication: (() throws -> Void)?) throws {
        let sourceName = try relativePath(of: source)
        let destinationName = try relativePath(of: destination)
        try requireExclusiveRename(at: destination)
        try beforePublication?()
        guard Darwin.renameatx_np(
            descriptor, sourceName, descriptor, destinationName,
            UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY)
        ) == 0 else { throw Self.failure() }
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
                try root.createFile(at: url, beforePublication: beforeRootedMutation)
            case let .createDirectory(url):
                try root.createDirectory(at: url, beforePublication: beforeRootedMutation)
            case let .move(source, destination):
                try root.move(source, to: destination, beforePublication: beforeRootedMutation)
            case let .copy(source, destination):
                try FileTreeRootedCopy.copy(source, to: destination, root: root,
                                            beforePublication: beforeRootedMutation)
            case let .trash(url):
                try await trash(at: url)
            }
        }.value
    }
}
