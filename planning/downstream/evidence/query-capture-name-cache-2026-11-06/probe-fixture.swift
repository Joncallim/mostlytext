import Foundation

enum Fixtures {
    /// Generates a deterministic Markdown string by repeating `line` until it is
    /// at least `totalBytes` UTF-8 bytes long.
    static func markdownRepeating(line: String, totalBytes: Int) -> String {
        let lineBytes = line.utf8.count
        let count = max(1, totalBytes / lineBytes)
        var result = String(repeating: line, count: count)
        while result.utf8.count < totalBytes {
            result.append(line)
        }
        return result
    }
}
