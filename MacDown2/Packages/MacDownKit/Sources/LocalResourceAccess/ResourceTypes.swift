import Foundation

/// Why a contained read was refused or failed. Callers map these to their own policy (HTTP-style status, diagnostic);
/// none of them carries an outside path or byte.
public enum ResourceReadError: Error, Equatable, Sendable {
    /// The reference or the object it names is outside what the grant authorises.
    case denied
    /// The granted directory's name no longer refers to the directory that was granted.
    case changedRoot
    /// The opened object is not a regular file (FIFO, device, directory, socket).
    case nonRegular
    /// The object is, or grew, larger than the trusted cap.
    case oversized
    /// The object's identity, size or modification time changed while it was being read.
    case changedDuringRead
    case cancelled
    /// The lease the read was issued against has been closed (disposal, not cancellation).
    case leaseClosed
    /// The kernel rejected the containment open flags, so containment cannot be enforced; callers must not fall back.
    case unsupportedEnforcement
    /// The object does not exist or could not be opened; the associated value is the errno.
    case unavailable(Int32)
    /// The malformed or unsupported reference was rejected before any filesystem access.
    case invalidReference
}

/// Stable identity of an opened filesystem object (device + inode).
public struct ResourceIdentity: Equatable, Hashable, Sendable {
    public let device: Int64
    public let inode: UInt64

    init(_ info: stat) {
        device = Int64(info.st_dev)
        inode = UInt64(info.st_ino)
    }
}

/// Immutable bytes that were actually admitted by the reader, plus where they came from. It carries no URL for a
/// later unguarded reopen.
public struct ResourceSnapshot: Sendable, Equatable {
    public let bytes: Data
    public let identity: ResourceIdentity
    /// Resolved target leaf used by the constrained open, rather than an
    /// authored symlink alias. MIME decisions must describe those same bytes.
    public let name: String
    public let mimeHint: String
}

/// Cooperative cancellation for a blocking read: the reader checks it between chunks.
public final class ResourceCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum MIMEHint {
    private static let table: [String: String] = [
        "html": "text/html", "htm": "text/html", "xhtml": "application/xhtml+xml",
        "css": "text/css", "js": "text/javascript", "mjs": "text/javascript", "json": "application/json",
        "svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "webp": "image/webp", "avif": "image/avif", "ico": "image/x-icon",
        "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "otf": "font/otf",
        "xml": "application/xml", "txt": "text/plain", "md": "text/markdown",
        "mp4": "video/mp4", "webm": "video/webm", "mp3": "audio/mpeg", "wav": "audio/wav",
        "pdf": "application/pdf",
    ]

    static func hint(forName name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        return table[ext] ?? "application/octet-stream"
    }
}
