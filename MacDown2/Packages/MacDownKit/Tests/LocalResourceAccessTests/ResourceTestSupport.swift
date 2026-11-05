import Darwin
import Foundation
@testable import LocalResourceAccess
import Testing

/// Shared fixtures for the contained-reader suites: a disposable root with a separate "outside" sentinel directory.
enum ResourceTestSupport {
    static let secret = "OUTSIDE-SECRET-BYTES"

    struct Tree {
        let base: URL
        let root: URL
        let outside: URL

        func write(_ text: String, to relative: String) throws {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: false, encoding: .utf8)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    static func makeTree() throws -> Tree {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("lra-\(UUID().uuidString)")
        let root = base.appendingPathComponent("root")
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try secret.write(to: outside.appendingPathComponent("secret.txt"), atomically: false, encoding: .utf8)
        return Tree(base: base, root: root, outside: outside)
    }

    static func reference(_ path: String) throws -> ResourceReference {
        try ResourceReference.parse(path)
    }

    /// Open descriptors whose path lies under `base`. Counting by path (not the process-wide total) keeps the leak
    /// checks exact while other suites in the same process open and close their own descriptors.
    static func openDescriptorCount(under base: URL) -> Int {
        let canonical = base.resolvingSymlinksInPath().path
        return (0 ..< 1024).count { descriptor in
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(Int32(descriptor), F_GETPATH, &buffer) == 0 else { return false }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                .hasPrefix(canonical)
        }
    }

    static func leaked(_ snapshot: ResourceSnapshot?) -> Bool {
        guard let snapshot else { return false }
        return (String(bytes: snapshot.bytes, encoding: .utf8) ?? "").contains(secret)
    }
}
