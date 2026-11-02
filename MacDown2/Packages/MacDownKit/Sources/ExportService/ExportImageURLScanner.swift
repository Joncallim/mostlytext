import Foundation

/// Byte offsets only; never normalizes or reserializes authored HTML. This
/// recognizes a private token only in a complete quoted img/src attribute.
/// Missing/malformed contexts leave tokens unresolved and fail registration.
enum ExportImageURLScanner {
    struct Source {
        let range: Range<Int>
        let value: String
    }

    private struct Tag {
        let name: String
        let closing: Bool
        let end: Int
        let sources: [Source]
    }

    static func sources(in html: String) throws -> [Source] {
        let bytes = Array(html.utf8)
        var cursor = 0
        var rawText: String?
        var sources: [Source] = []
        while cursor < bytes.count {
            if cursor.isMultiple(of: 4096) {
                try Task.checkCancellation()
            }
            guard bytes[cursor] == 60 else { cursor += 1; continue }
            if let raw = rawText {
                guard raw != "plaintext", matches("</", at: cursor, in: bytes),
                      let closing = try tag(at: cursor, in: bytes), closing.closing, closing.name == raw
                else { cursor += 1; continue }
                rawText = nil
                cursor = closing.end
                continue
            }
            guard let opaqueEnd = try afterOpaqueMarkup(at: cursor, in: bytes) else { break }
            if opaqueEnd != cursor {
                cursor = opaqueEnd; continue
            }
            guard let tag = try tag(at: cursor, in: bytes) else {
                // An unfinished tag can contain arbitrary apparent markup.
                // Do not reinterpret its quoted contents as an image.
                break
            }
            sources.append(contentsOf: tag.sources)
            if !tag.closing, rawElements.contains(tag.name) {
                rawText = tag.name
            }
            cursor = tag.end
        }
        return sources
    }

    private static func afterOpaqueMarkup(at cursor: Int, in bytes: [UInt8]) throws -> Int? {
        if matches("<![CDATA[", at: cursor, in: bytes) {
            return try cdataEnd(from: cursor + 9, in: bytes)
        }
        if matches("<!--", at: cursor, in: bytes) {
            return try commentEnd(at: cursor, in: bytes)
        }
        return cursor
    }

    private static let rawElements: Set<String> = [
        "script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes", "plaintext",
    ]

    private struct Attribute {
        let name: String
        let range: Range<Int>?
        let quoted: Bool
    }

    private static func tag(at start: Int, in bytes: [UInt8]) throws -> Tag? {
        var cursor = start + 1
        guard cursor < bytes.count else { return nil }
        if bytes[cursor] == 33 || bytes[cursor] == 63 {
            guard let end = try declarationEnd(from: cursor, in: bytes) else { return nil }
            return Tag(name: "", closing: true, end: end, sources: [])
        }
        guard let header = header(at: cursor, in: bytes) else { return nil }
        let (name, closing) = (header.name, header.closing)
        cursor = header.end
        var sources: [Source] = []
        while cursor < bytes.count {
            if bytes[cursor] == 62 {
                return Tag(name: name, closing: closing, end: cursor + 1, sources: sources)
            }
            if space(bytes[cursor]) || bytes[cursor] == 47 {
                cursor += 1; continue
            }
            guard let attribute = try attribute(at: &cursor, in: bytes) else { return nil }
            if name == "img", !closing, let source = source(attribute, in: bytes) {
                sources.append(source)
            }
        }
        return nil
    }

    private struct Header {
        let name: String
        let closing: Bool
        let end: Int
    }

    private static func header(at start: Int, in bytes: [UInt8]) -> Header? {
        var cursor = start
        let closing = bytes[cursor] == 47
        if closing {
            cursor += 1
        }
        let nameStart = cursor
        while cursor < bytes.count, nameByte(bytes[cursor]) {
            cursor += 1
        }
        guard cursor > nameStart, let name = String(bytes: bytes[nameStart ..< cursor], encoding: .utf8)?.lowercased()
        else { return nil }
        return Header(name: name, closing: closing, end: cursor)
    }

    private static func source(_ attribute: Attribute, in bytes: [UInt8]) -> Source? {
        guard attribute.name == "src", attribute.quoted, let range = attribute.range,
              let value = String(bytes: bytes[range], encoding: .utf8) else { return nil }
        return Source(range: range, value: value)
    }

    private static func attribute(at cursor: inout Int, in bytes: [UInt8]) throws -> Attribute? {
        let start = cursor
        while cursor < bytes.count, !space(bytes[cursor]), ![61, 62, 47].contains(bytes[cursor]) {
            cursor += 1
        }
        guard cursor > start, let name = String(bytes: bytes[start ..< cursor], encoding: .utf8)?.lowercased()
        else { return nil }
        skipSpace(at: &cursor, in: bytes)
        guard cursor < bytes.count else { return nil }
        guard bytes[cursor] == 61 else { return Attribute(name: name, range: nil, quoted: false) }
        cursor += 1
        skipSpace(at: &cursor, in: bytes)
        guard cursor < bytes.count else { return nil }
        let quoted = bytes[cursor] == 34 || bytes[cursor] == 39
        guard let range = try value(at: &cursor, in: bytes, quoted: quoted) else { return nil }
        return Attribute(name: name, range: range, quoted: quoted)
    }

    private static func value(at cursor: inout Int, in bytes: [UInt8], quoted: Bool) throws -> Range<Int>? {
        let quote = bytes[cursor]
        if quoted {
            cursor += 1
        }
        let start = cursor
        while cursor < bytes.count {
            if cursor.isMultiple(of: 4096) {
                try Task.checkCancellation()
            }
            if quoted ? bytes[cursor] == quote : (space(bytes[cursor]) || bytes[cursor] == 62) {
                break
            }
            cursor += 1
        }
        let range = start ..< cursor
        if quoted {
            guard cursor < bytes.count else { return nil }
            cursor += 1
        }
        return range
    }

    private static func skipSpace(at cursor: inout Int, in bytes: [UInt8]) {
        while cursor < bytes.count, space(bytes[cursor]) {
            cursor += 1
        }
    }

    private static func declarationEnd(from start: Int, in bytes: [UInt8]) throws -> Int? {
        var cursor = start
        var quote: UInt8?
        while cursor < bytes.count {
            if cursor.isMultiple(of: 4096) {
                try Task.checkCancellation()
            }
            let byte = bytes[cursor]
            if let delimiter = quote {
                if byte == delimiter {
                    quote = nil
                }
            } else if byte == 34 || byte == 39 {
                quote = byte
            } else if byte == 62 {
                return cursor + 1
            }
            cursor += 1
        }
        return nil
    }

    private static func nameByte(_ byte: UInt8) -> Bool {
        (65 ... 90).contains(byte) || (97 ... 122).contains(byte) || (48 ... 57).contains(byte)
            || [45, 58, 95].contains(byte)
    }

    private static func space(_ byte: UInt8) -> Bool {
        [9, 10, 12, 13, 32].contains(byte)
    }

    private static func matches(_ text: String, at start: Int, in bytes: [UInt8]) -> Bool {
        let needle = Array(text.utf8)
        return bytes.count - start >= needle.count && bytes[start ..< start + needle.count].elementsEqual(needle)
    }

    private static func cdataEnd(from start: Int, in bytes: [UInt8]) throws -> Int? {
        var cursor = start
        while bytes.count - cursor >= 3 {
            if cursor.isMultiple(of: 4096) {
                try Task.checkCancellation()
            }
            if bytes[cursor] == 93, bytes[cursor + 1] == 93, bytes[cursor + 2] == 62 {
                return cursor + 3
            }
            cursor += 1
        }
        return nil
    }

    private static func commentEnd(at start: Int, in bytes: [UInt8]) throws -> Int? {
        var cursor = start + 4
        if matches(">", at: cursor, in: bytes) {
            return cursor + 1
        }
        if matches("->", at: cursor, in: bytes) {
            return cursor + 2
        }
        while cursor < bytes.count {
            if matches("-->", at: cursor, in: bytes) {
                return cursor + 3
            }
            if matches("--!>", at: cursor, in: bytes) {
                return cursor + 4
            }
            cursor += 1
        }
        return nil
    }
}
