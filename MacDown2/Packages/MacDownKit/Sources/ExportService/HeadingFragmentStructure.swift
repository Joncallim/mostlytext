import Foundation

/// A narrow structural proof for generated fragments embedded in cmark output.
/// Accepted fragments cannot add identifiers, headings, raw-text/foreign parsing
/// contexts, or unbalanced elements. Unknown syntax needs emitted-DOM analysis.
/// This is neither an HTML sanitizer nor resource/URL authorization.
enum HeadingFragmentStructure {
    static let maximumDepth = 64

    static func accepts(_ html: String, isBlock: Bool) -> Bool {
        var source = html
        return source.withUTF8 { bytes in
            var scanner = Scanner(bytes: bytes, isBlock: isBlock)
            return scanner.accepts()
        }
    }

    private enum Tag: String {
        case unorderedList = "ul"
        case orderedList = "ol"
        case listItem = "li"
        case paragraph = "p"
        case anchor = "a"
        case emphasis = "em"
        case strong
        case code
        case deletion = "del"
        case image = "img"
        case lineBreak = "br"

        var isVoid: Bool {
            self == .image || self == .lineBreak
        }

        var isPhrasing: Bool {
            ![.unorderedList, .orderedList, .listItem, .paragraph].contains(self)
        }

        func permits(_ child: Tag) -> Bool {
            switch self {
            case .unorderedList, .orderedList: child == .listItem
            case .listItem: child != .listItem
            default: child.isPhrasing
            }
        }

        func permits(attribute: String) -> Bool {
            switch self {
            case .anchor: ["href", "title"].contains(attribute)
            case .image: ["src", "alt", "width", "height", "title"].contains(attribute)
            case .orderedList: attribute == "start"
            default: false
            }
        }
    }

    /// Byte storage is borrowed for this synchronous call only. Tag/attribute
    /// names have small bounds; long data URIs are scanned without copying them.
    private struct Scanner {
        let bytes: UnsafeBufferPointer<UInt8>
        let isBlock: Bool
        var position = 0
        var stack: [Tag] = []

        mutating func accepts() -> Bool {
            while position < bytes.count {
                if bytes[position] == 0x3C {
                    guard element() else { return false }
                } else {
                    let byte = bytes[position]
                    guard byte >= 0x20 || Self.isWhitespace(byte) else { return false }
                    if stack.last == .unorderedList || stack.last == .orderedList {
                        guard Self.isWhitespace(byte) else { return false }
                    }
                    position += 1
                }
            }
            return stack.isEmpty
        }

        private mutating func element() -> Bool {
            position += 1
            let closing = consume(0x2F)
            guard let name = name(), let tag = Tag(rawValue: name) else { return false }
            if closing {
                whitespace()
                guard !tag.isVoid, consume(0x3E), stack.last == tag else { return false }
                stack.removeLast()
                return true
            }
            if let parent = stack.last {
                guard parent.permits(tag) else { return false }
            } else {
                guard tag != .listItem, isBlock || tag.isPhrasing else { return false }
            }
            // An inline custom node may already be inside an authored link.
            // A generated anchor there could trigger HTML's adoption repair.
            guard tag != .anchor || (isBlock && !stack.contains(.anchor)), attributes(for: tag) else { return false }
            if !tag.isVoid {
                guard stack.count < HeadingFragmentStructure.maximumDepth else { return false }
                stack.append(tag)
            }
            return true
        }

        private mutating func attributes(for tag: Tag) -> Bool {
            var seen: Set<String> = []
            while position < bytes.count {
                let separated = whitespace()
                if consume(0x3E) {
                    return true
                }
                if consume(0x2F) {
                    return tag.isVoid && consume(0x3E)
                }
                guard separated, let attribute = name(), tag.permits(attribute: attribute),
                      seen.insert(attribute).inserted else { return false }
                whitespace()
                guard consume(0x3D) else { return false }
                whitespace()
                guard position < bytes.count, bytes[position] == 0x22 || bytes[position] == 0x27 else {
                    return false
                }
                let quote = bytes[position]
                position += 1
                while position < bytes.count, bytes[position] != quote {
                    // Quotes/entities in values cannot become HTML delimiters.
                    // Reject literal '<' and controls to keep this grammar narrow.
                    guard bytes[position] >= 0x20, bytes[position] != 0x3C, bytes[position] != 0x7F else {
                        return false
                    }
                    position += 1
                }
                guard consume(quote) else { return false }
            }
            return false
        }

        private mutating func name() -> String? {
            let start = position
            while position < bytes.count, (0x61 ... 0x7A).contains(bytes[position]) {
                position += 1
                guard position - start <= 16 else { return nil }
            }
            guard position > start else { return nil }
            return String(decoding: bytes[start ..< position], as: Unicode.UTF8.self)
        }

        @discardableResult
        private mutating func whitespace() -> Bool {
            let start = position
            while position < bytes.count, Self.isWhitespace(bytes[position]) {
                position += 1
            }
            return position > start
        }

        private static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }

        private mutating func consume(_ byte: UInt8) -> Bool {
            guard position < bytes.count, bytes[position] == byte else { return false }
            position += 1
            return true
        }
    }
}
