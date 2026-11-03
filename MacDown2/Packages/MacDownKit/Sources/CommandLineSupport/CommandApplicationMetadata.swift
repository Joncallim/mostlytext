import Darwin
import Foundation

public enum EmbeddedCommandFailure: Error, Sendable, Equatable {
    case invalidContainer
    case invalidIdentity
    case unverifiedSignature
}

/// The locator must reject non-regular metadata before a potentially blocking
/// read. This helper never launches an application or touches its stores.
enum CommandApplicationMetadata {
    static let maximumBytes = 65536

    /// The test hook changes real objects after open, before reading. Production
    /// passes no hook; there is no alternative pathname read on failure.
    static func read(at url: URL, afterOpen: (() throws -> Void)? = nil) throws -> Data {
        guard url.isFileURL else { throw EmbeddedCommandFailure.invalidContainer }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw EmbeddedCommandFailure.invalidContainer }
        defer { _ = Darwin.close(descriptor) }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0, initial.st_mode & S_IFMT == S_IFREG,
              initial.st_size >= 0, initial.st_size <= maximumBytes else {
            throw EmbeddedCommandFailure.invalidContainer
        }
        try afterOpen?()
        let bytes = try readBytes(from: descriptor, expectedSize: Int(initial.st_size))
        var final = stat()
        var named = stat()
        guard fstat(descriptor, &final) == 0, lstat(url.path, &named) == 0,
              unchanged(initial, final), unchanged(initial, named), bytes.count == initial.st_size else {
            throw EmbeddedCommandFailure.invalidContainer
        }
        return bytes
    }

    private static func readBytes(from descriptor: Int32, expectedSize: Int) throws -> Data {
        var bytes = Data()
        bytes.reserveCapacity(expectedSize)
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let wanted = min(buffer.count, maximumBytes - bytes.count + 1)
            let count = Darwin.read(descriptor, &buffer, wanted)
            if count < 0, errno == EINTR {
                continue
            }
            guard count >= 0, count <= maximumBytes - bytes.count else {
                throw EmbeddedCommandFailure.invalidContainer
            }
            if count == 0 {
                return bytes
            }
            bytes.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func unchanged(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_mode == rhs.st_mode
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}
