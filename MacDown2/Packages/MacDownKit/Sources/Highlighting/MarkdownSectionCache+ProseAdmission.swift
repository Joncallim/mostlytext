import Foundation
import SwiftTreeSitter

extension MarkdownSectionCache {
    /// A standalone paragraph parse has a synthetic outer section. Admit it
    /// only when that wrapper contains one error-free, full-width paragraph;
    /// the retained snapshot still supplies inline and injection captures.
    static func replacementNode(_ node: Node, replacing prior: Node,
                                contentLength: Int, singleEntry: Bool) -> Node? {
        if node.nodeType == prior.nodeType {
            return node
        }
        guard singleEntry, prior.nodeType == "paragraph", node.nodeType == "section",
              !node.hasError, node.range == NSRange(location: 0, length: contentLength),
              node.childCount == 1, let paragraph = node.child(at: 0),
              paragraph.nodeType == "paragraph", !paragraph.hasError,
              paragraph.range == node.range
        else { return nil }
        return paragraph
    }

    /// Require both neighboring UTF-16 units to be alphanumeric. This also
    /// refuses surrogate boundaries and word-edge/structural insertions.
    static func isInteriorWordInsertion(source: NSString, at location: Int) -> Bool {
        guard location > 0, location < source.length else { return false }
        let word = CharacterSet.alphanumerics
        let left = source.substring(with: NSRange(location: location - 1, length: 1))
        let right = source.substring(with: NSRange(location: location, length: 1))
        return left.unicodeScalars.allSatisfy(word.contains)
            && right.unicodeScalars.allSatisfy(word.contains)
    }

    static func isInteriorSpaceInsertion(source: NSString, at location: Int, replacement: String) -> Bool {
        guard location > 0, location < source.length,
              !replacement.isEmpty, replacement.unicodeScalars.allSatisfy({ $0 == " " || $0 == "\t" })
        else { return false }
        let word = CharacterSet.alphanumerics
        let left = source.substring(with: NSRange(location: location - 1, length: 1))
        let right = source.substring(with: NSRange(location: location, length: 1))
        return left.unicodeScalars.allSatisfy(word.contains)
            && right.unicodeScalars.allSatisfy { word.contains($0) || $0 == " " || $0 == "\t" }
    }

    static func safeProseEdit(old: String, replacement: String) -> Bool {
        let word = CharacterSet.alphanumerics.union(.nonBaseCharacters)
        return (old + replacement).unicodeScalars.allSatisfy { word.contains($0) || $0 == " " || $0 == "\t" }
    }

    /// Links, references, escapes, entities and block syntax can depend on
    /// text outside the local slice. Emoji-presentation scalars are ordinary
    /// inline text; unlike the broader symbols set, this excludes ASCII
    /// Markdown/math delimiters such as `$`, `#`, and `*`.
    static func safeProseBody(_ body: String) -> Bool {
        let word = CharacterSet.alphanumerics.union(.nonBaseCharacters)
        return body.unicodeScalars.allSatisfy { word.contains($0) || $0 == " " || $0 == "\t"
            || $0 == "*" || $0 == "_" || $0 == "`" || $0.properties.isEmojiPresentation
        }
    }

    static func isBoundedHeadingEdit(entry: Section, edit: NSRange, source: NSString) -> Bool {
        let range = entry.globalRange
        guard entry.node.nodeType == "section", range.length > 0, range.length <= windowLimit,
              range.location <= edit.location, NSMaxRange(edit) <= NSMaxRange(range)
        else { return false }
        let slice = source.substring(with: range)
        return isBoundedHeadingEdit(
            section: slice,
            edit: NSRange(location: edit.location - range.location, length: edit.length)
        )
    }

    /// The unpaired history path has only its cached section, not the old
    /// whole-document source. Apply the same heading boundary checks to it.
    static func isBoundedHeadingEdit(section slice: String, edit: NSRange) -> Bool {
        let length = (slice as NSString).length
        guard length > 0, length <= windowLimit,
              edit.location >= 0, edit.length >= 0,
              edit.location <= length, edit.length <= length - edit.location
        else { return false }
        guard let lineEnd = slice.firstIndex(of: "\n") else { return false }
        let line = String(slice[..<lineEnd])
        let leadingHashes = line.prefix(while: { $0 == "#" }).count
        guard (1 ... 6).contains(leadingHashes), line.dropFirst(leadingHashes).first == " ",
              slice[lineEnd...].unicodeScalars.allSatisfy({ $0 == "\n" || $0 == "\r" }),
              safeProseBody(String(line.dropFirst(leadingHashes + 1)))
        else { return false }
        let contentStart = leadingHashes + 1
        let contentEnd = (line as NSString).length
        return edit.location > contentStart && NSMaxRange(edit) < contentEnd
    }
}
