import Foundation
import JSONSupport

/// Readable salvage is not permission to overwrite an authoritative session.
public enum WorkspaceSessionAdmission: Sendable, Equatable {
    public static let maximumBytes = 16 * 1024 * 1024
    case absent
    case readable(WorkspaceSession)
    case partiallyReadable(WorkspaceSession)
    case unsupported
    case unreadable
    case tooLarge

    public var session: WorkspaceSession? {
        switch self {
        case let .readable(value), let .partiallyReadable(value): value
        default: nil
        }
    }

    public var permitsPublication: Bool {
        switch self {
        case .absent, .readable: true
        default: false
        }
    }

    public static func decode(_ bytes: Data?) -> Self {
        guard let bytes else { return .absent }
        guard bytes.count <= maximumBytes else { return .tooLarge }
        guard let text = String(data: bytes, encoding: .utf8),
              case let .valid(root) = JSONParser.parse(text), case let .object(members) = root.value else {
            return .unreadable
        }
        let fields = Dictionary(uniqueKeysWithValues: members.map { ($0.key, $0.value) })
        guard case let .number(version) = fields["version"]?.value else { return .unreadable }
        if version != "1" {
            return version.utf8.allSatisfy { (48 ... 57).contains($0) } && version != "0" ? .unsupported : .unreadable
        }
        guard Set(fields.keys).isSubset(of: Set(WorkspaceSession.CodingKeys.allCases.map(\.rawValue))) else {
            return .unsupported
        }
        guard case let .array(tabs) = fields["tabs"]?.value,
              let session = try? JSONDecoder().decode(WorkspaceSession.self, from: bytes) else { return .unreadable }
        let allowed = Set(TabRecord.CodingKeys.allCases.map(\.rawValue))
        let complete = session.tabs.count == tabs.count && Set(session.tabs.map(\.id)).count == session.tabs.count &&
            tabs.allSatisfy { node in
                guard case let .object(values) = node.value else { return false }
                return Set(values.map(\.key)).isSubset(of: allowed)
            } && retainedNestedFields(tabs, decoded: session.tabs)
        return complete ? .readable(session) : .partiallyReadable(session)
    }

    /// A newer nested encoding/syntax payload must not disappear merely
    /// because its outer tab decoded. Compare known encoded structure too.
    private static func retainedNestedFields(_ tabs: [JSONNode], decoded: [TabRecord]) -> Bool {
        guard tabs.count == decoded.count else { return false }
        return zip(tabs, decoded).allSatisfy { original, tab in
            guard let bytes = try? JSONEncoder().encode(tab), let text = String(data: bytes, encoding: .utf8),
                  case let .valid(encoded) = JSONParser.parse(text),
                  case let .object(fields) = original.value else { return false }
            for field in fields where ["cursorPosition", "selectionLength"].contains(field.key) {
                if case let .number(raw) = field.value.value {
                    guard let value = Int(raw), value >= 0 else { return false }
                }
            }
            return retainsKeys(original, encoded: encoded, allowAbsentNull: true)
        }
    }

    private static func retainsKeys(_ original: JSONNode, encoded: JSONNode, allowAbsentNull: Bool = false) -> Bool {
        switch (original.value, encoded.value) {
        case let (.object(before), .object(after)):
            let fields = Dictionary(uniqueKeysWithValues: after.map { ($0.key, $0.value) })
            return before.allSatisfy { field in
                guard let value = fields[field.key] else {
                    if allowAbsentNull, case .null = field.value.value {
                        return true
                    }
                    return false
                }
                return retainsKeys(field.value, encoded: value)
            }
        case let (.array(before), .array(after)):
            return before.count == after.count && zip(before, after).allSatisfy { retainsKeys($0, encoded: $1) }
        case (.object, _), (.array, _): return false
        default: return true
        }
    }
}
