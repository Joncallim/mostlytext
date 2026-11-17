import Foundation

/// Deterministic JSON formatting options.
public struct JSONFormatOptions: Sendable, Equatable {
    /// Spaces per indentation level.
    public var indentWidth: Int
    /// Sort object keys recursively in Unicode scalar order. Arrays always
    /// retain source order.
    public var sortKeys: Bool
    /// Emit a single trailing line terminator after the root value.
    public var trailingNewline: Bool

    public init(indentWidth: Int = 2, sortKeys: Bool = false, trailingNewline: Bool = true) {
        self.indentWidth = indentWidth
        self.sortKeys = sortKeys
        self.trailingNewline = trailingNewline
    }

    public static let pretty = JSONFormatOptions()
}

/// Deterministic pretty-printer for valid JSON (EPIC-11 §3.5).
///
/// Policy:
/// - Only valid documents are formatted; invalid input yields the parser's
///   single diagnostic and no output.
/// - Object key order: source order by default; `sortKeys` sorts keys by
///   Unicode scalar value, recursively. Array order is always preserved.
/// - Indentation is `indentWidth` spaces; non-empty containers place each
///   member/element on its own line; empty containers emit `{}` / `[]`.
/// - Strings are re-encoded canonically: `"`, `\`, and control characters
///   (< U+0020) are escaped (`\uXXXX`), all other scalars — including
///   non-ASCII — are emitted verbatim. Numbers keep their exact source text.
/// - The output ends with exactly one line terminator when `trailingNewline`
///   is set. CRLF sources (every newline is `\r\n`) produce CRLF output;
///   everything else produces LF. BOMs are a byte-level FileStore concern and
///   are preserved through the document's encoding metadata, not by the
///   formatter.
/// - Formatting never runs on duplicate-key documents: the parser rejects
///   them first with a stable diagnostic.
public enum JSONFormatter {
    public static func format(_ text: String, options: JSONFormatOptions = .pretty) -> JSONFormatOutcome {
        switch JSONParser.parse(text) {
        case let .invalid(diagnostic):
            return .invalid(diagnostic)
        case let .valid(node):
            let lineEnding = sourceLineEnding(text)
            var writer = Writer(indentWidth: max(options.indentWidth, 0), lineEnding: lineEnding)
            write(node, sortKeys: options.sortKeys, indent: 0, into: &writer)
            if options.trailingNewline {
                writer.append(lineEnding)
            }
            return .formatted(writer.output)
        }
    }

    private struct Writer {
        let indentWidth: Int
        let lineEnding: String
        var output = ""

        mutating func append(_ string: String) {
            output += string
        }

        mutating func indent(_ level: Int) {
            output += String(repeating: " ", count: indentWidth * level)
        }

        mutating func newline() {
            output += lineEnding
        }
    }

    private static func write(_ node: JSONNode, sortKeys: Bool, indent: Int, into writer: inout Writer) {
        switch node.value {
        case let .object(members):
            writeObject(members, sortKeys: sortKeys, indent: indent, into: &writer)
        case let .array(elements):
            writeArray(elements, sortKeys: sortKeys, indent: indent, into: &writer)
        case let .string(value):
            writer.append(encodeString(value))
        case let .number(raw):
            writer.append(raw)
        case let .boolean(value):
            writer.append(value ? "true" : "false")
        case .null:
            writer.append("null")
        }
    }

    private static func writeObject(
        _ members: [JSONObjectMember],
        sortKeys: Bool,
        indent: Int,
        into writer: inout Writer
    ) {
        if members.isEmpty {
            writer.append("{}")
            return
        }
        writer.append("{")
        writer.newline()
        let ordered = sortKeys
            ? members.sorted { $0.key.unicodeScalars.lexicographicallyPrecedes($1.key.unicodeScalars) }
            : members
        for (index, member) in ordered.enumerated() {
            writer.indent(indent + 1)
            writer.append(encodeString(member.key))
            writer.append(": ")
            write(member.value, sortKeys: sortKeys, indent: indent + 1, into: &writer)
            if index < ordered.count - 1 {
                writer.append(",")
            }
            writer.newline()
        }
        writer.indent(indent)
        writer.append("}")
    }

    private static func writeArray(
        _ elements: [JSONNode],
        sortKeys: Bool,
        indent: Int,
        into writer: inout Writer
    ) {
        if elements.isEmpty {
            writer.append("[]")
            return
        }
        writer.append("[")
        writer.newline()
        for (index, element) in elements.enumerated() {
            writer.indent(indent + 1)
            write(element, sortKeys: sortKeys, indent: indent + 1, into: &writer)
            if index < elements.count - 1 {
                writer.append(",")
            }
            writer.newline()
        }
        writer.indent(indent)
        writer.append("]")
    }

    /// Canonical string encoding: escape quotes, backslashes, and control
    /// characters; emit every other scalar verbatim.
    static func encodeString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0x08: result += "\\b"
            case 0x0C: result += "\\f"
            case 0x0A: result += "\\n"
            case 0x0D: result += "\\r"
            case 0x09: result += "\\t"
            case 0x00 ... 0x1F:
                result += String(format: "\\u%04X", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }

    /// Dominant line ending: CRLF when every line terminator in the source is
    /// CRLF, otherwise LF. CR-only and mixed-break input is deliberately
    /// normalized to LF by this formatter policy.
    static func sourceLineEnding(_ text: String) -> String {
        let withoutCRLF = text.replacingOccurrences(of: "\r\n", with: "")
        if text.contains("\r\n"), !withoutCRLF.contains("\n"), !withoutCRLF.contains("\r") {
            return "\r\n"
        }
        return "\n"
    }
}
