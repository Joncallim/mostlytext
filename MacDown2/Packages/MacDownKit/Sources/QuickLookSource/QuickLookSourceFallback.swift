import Darwin
import FileCore
import Foundation

public enum QuickLookSourceError: Error, Sendable, Equatable {
    case invalidURL
    case openFailed
    case notRegularFile
    case sourceTooLarge
    case readFailed
    case sourceChanged
}

/// A passive Quick Look reply for one system-supplied Markdown file. This
/// bounded source view remains useful when derived rendering is unavailable.
public enum QuickLookSourceFallback {
    public static let maximumSourceBytes = 1 << 20

    public static func replyHTML(for fileURL: URL) throws -> Data {
        let bytes = try readSelectedFile(fileURL)
        let decoded = try FileByteDecoder.decode(bytes, maximumBytes: maximumSourceBytes)
        return html(for: decoded.text)
    }

    /// No authored byte is emitted as markup, a URL or a resource reference.
    private static func html(for source: String) -> Data {
        let escaped = source.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
        return Data("""
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; base-uri 'none'; form-action 'none'">
        </head><body><pre>\(escaped)</pre></body></html>
        """.utf8)
    }

    private static func readSelectedFile(_ fileURL: URL) throws -> Data {
        guard fileURL.isFileURL else { throw QuickLookSourceError.invalidURL }
        // The Quick Look grant is for this selected file, never its parent.
        let descriptor = open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW_ANY)
        guard descriptor >= 0 else { throw QuickLookSourceError.openFailed }
        defer { close(descriptor) }

        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw QuickLookSourceError.readFailed }
        guard before.st_mode & S_IFMT == S_IFREG else { throw QuickLookSourceError.notRegularFile }
        guard before.st_size >= 0, before.st_size <= maximumSourceBytes else {
            throw QuickLookSourceError.sourceTooLarge
        }

        let bytes = try readExactly(descriptor, count: Int(before.st_size))

        var after = stat()
        guard fstat(descriptor, &after) == 0 else { throw QuickLookSourceError.readFailed }
        guard sameFileSnapshot(before, after) else { throw QuickLookSourceError.sourceChanged }
        return bytes
    }

    private static func readExactly(_ descriptor: Int32, count expected: Int) throws -> Data {
        var bytes = Data(count: expected)
        if expected > 0 {
            try bytes.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { throw QuickLookSourceError.readFailed }
                var offset = 0
                while offset < expected {
                    let count = readRetry(descriptor, base.advanced(by: offset), expected - offset)
                    guard count >= 0 else { throw QuickLookSourceError.readFailed }
                    guard count > 0 else { throw QuickLookSourceError.sourceChanged }
                    offset += count
                }
            }
        }
        var extra: UInt8 = 0
        let extraCount = readRetry(descriptor, &extra, 1)
        guard extraCount >= 0 else { throw QuickLookSourceError.readFailed }
        guard extraCount == 0 else { throw QuickLookSourceError.sourceChanged }
        return bytes
    }

    private static func sameFileSnapshot(_ before: stat, _ after: stat) -> Bool {
        before.st_dev == after.st_dev
            && before.st_ino == after.st_ino
            && before.st_mode == after.st_mode
            && before.st_size == after.st_size
            && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec
            && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
            && before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec
            && before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
    }

    private static func readRetry(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        while true {
            let result = Darwin.read(descriptor, buffer, count)
            if result < 0, errno == EINTR {
                continue
            }
            return result
        }
    }
}
