import CryptoKit
import Foundation

/// Hash exact input bytes without allocating a second complete source buffer.
enum MarkdownSourceFingerprint {
    static func sha256(_ source: String) -> String {
        var hasher = SHA256()
        if source.utf8.withContiguousStorageIfAvailable({ bytes in
            hasher.update(bufferPointer: UnsafeRawBufferPointer(bytes))
        }) == nil {
            var chunk = [UInt8]()
            chunk.reserveCapacity(64 * 1024)
            for byte in source.utf8 {
                chunk.append(byte)
                if chunk.count == 64 * 1024 {
                    chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
