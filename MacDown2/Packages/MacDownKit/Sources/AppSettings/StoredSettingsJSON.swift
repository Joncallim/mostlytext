import Foundation
import JSONSupport

/// Read-only admission before a whole-domain save can discard unknown data.
enum StoredSettingsJSON {
    enum Version { case current, future, malformed }

    static func fields(in raw: Data) -> [String: JSONNode]? {
        guard raw.count <= 1_048_576, let text = String(data: raw, encoding: .utf8),
              case let .valid(root) = JSONParser.parse(text), case let .object(members) = root.value else {
            return nil
        }
        var fields: [String: JSONNode] = [:]
        for member in members {
            // The parser preserves distinct Unicode spellings. A Swift
            // dictionary would merge canonical equivalents, so refuse them.
            guard fields.updateValue(member.value, forKey: member.key) == nil else { return nil }
        }
        return fields
    }

    static func version(in fields: [String: JSONNode]) -> Version? {
        guard let node = fields["schemaVersion"] else { return nil }
        guard case let .number(raw) = node.value, !raw.hasPrefix("-") else { return .malformed }
        let parts = raw.split(whereSeparator: { $0 == "e" || $0 == "E" })
        guard let coefficient = parts.first else { return .malformed }
        let decimal = coefficient.split(separator: ".", omittingEmptySubsequences: false)
        let fractionCount = decimal.count == 2 ? decimal[1].utf8.count : 0
        let digits = coefficient.utf8.filter { $0 != UInt8(ascii: ".") }.drop { $0 == UInt8(ascii: "0") }
        guard !digits.isEmpty else { return .malformed }
        let trailingZeros = digits.reversed().prefix { $0 == UInt8(ascii: "0") }.count
        let exponent: Int
        if parts.count == 2 {
            guard let parsed = Int(parts[1]) else {
                return parts[1].hasPrefix("-") ? .malformed : .future
            }
            // A scale beyond the entire admitted spelling cannot be
            // cancelled by its coefficient. Clamp before doing arithmetic.
            let bound = raw.utf8.count + 1
            exponent = min(max(parsed, -bound), bound)
        } else {
            exponent = 0
        }
        let scale = exponent - fractionCount + trailingZeros
        guard scale >= 0 else { return .malformed }
        return scale == 0 && digits.count - trailingZeros == 1 && digits.first == UInt8(ascii: "1")
            ? .current : .future
    }
}
