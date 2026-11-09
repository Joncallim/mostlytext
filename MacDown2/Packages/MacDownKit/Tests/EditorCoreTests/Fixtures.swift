import Foundation

/// Deterministic Markdown fixtures for performance tests.
enum Fixtures {
    /// Generates complete Markdown blocks until the UTF-8 source reaches
    /// `targetByteCount`, with less than one block of overshoot.
    ///
    /// The output mixes paragraphs, headers, lists, and code blocks so the
    /// text system exercises a realistic variety of line lengths and syntax
    /// markers without relying on external files.
    static func markdown(targetByteCount: Int) -> String {
        let line = "The quick brown fox jumps over the lazy dog. "
        let paragraph = String(repeating: line, count: 10) + "\n\n"

        var result = ""
        result.reserveCapacity(targetByteCount)
        var byteCount = 0
        var index = 0

        repeat {
            let block: String = switch index % 5 {
            case 0:
                "# Heading \(index)\n\n" + paragraph
            case 1:
                "- List item \(index)-a\n"
                    + "- List item \(index)-b\n"
                    + "- List item \(index)-c\n\n"
            case 2:
                "> A blockquote that spans a few words so it has some length.\n\n"
            case 3:
                "```\nlet x = \(index)\nlet y = x + 1\n```\n\n"
            default:
                paragraph
            }

            result += block
            byteCount += block.utf8.count
            index += 1
        } while byteCount < targetByteCount

        return result
    }
}
