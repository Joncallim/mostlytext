import CryptoKit
import Foundation
import JSONSupport

/// A frozen, read-only classification of the raw destination editor domain.
/// It never reads UserDefaults or grants permission to write a preference.
public struct LegacyEditorDestinationEvidence: Sendable, Equatable {
    public typealias Destination = LegacyEditorBooleanConversion.Destination

    public enum Status: Sendable, Equatable {
        case absent
        case knownCompatible
        case valid
        case malformed
        case unknownFuture
    }

    public let status: Status
    /// `absent`, or SHA-256 of the exact raw bytes. A later writer must
    /// recapture and compare this revision immediately before publication.
    public let rawRevision: String
    public let persisted: [Destination: Bool]
    public let provenAbsent: Set<Destination>

    private init(
        status: Status,
        rawRevision: String,
        persisted: [Destination: Bool] = [:],
        provenAbsent: Set<Destination> = []
    ) {
        self.status = status
        self.rawRevision = rawRevision
        self.persisted = persisted
        self.provenAbsent = provenAbsent
    }

    /// Classifies an explicitly supplied raw blob before creating a mutable
    /// settings model. Unsupported bytes remain the caller's responsibility
    /// to retain verbatim; this function does not normalize or serialize them.
    public static func decode(_ raw: Data?) -> Self {
        guard let raw else { return Self(status: .absent, rawRevision: "absent") }
        let revision = "sha256:" + SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        guard let fields = fields(in: raw) else { return Self(status: .malformed, rawRevision: revision) }
        let version = versionStatus(in: fields)
        if version == .malformed || version == .unknownFuture {
            return Self(status: version ?? .malformed, rawRevision: revision)
        }
        guard Set(fields.keys).isSubset(of: editorKeys) else {
            return Self(status: .unknownFuture, rawRevision: revision)
        }
        let missingStatusBar = fields["showsStatusBar"] == nil
        guard validEditor(fields: fields, raw: raw), !(version == .valid && missingStatusBar) else {
            return Self(status: .malformed, rawRevision: revision)
        }
        let persisted = persistedValues(in: fields)
        let provenAbsent = Set(Destination.allCases).subtracting(persisted.keys)
        return Self(
            status: missingStatusBar ? .knownCompatible : .valid,
            rawRevision: revision, persisted: persisted, provenAbsent: provenAbsent
        )
    }

    private static func fields(in raw: Data) -> [String: JSONNode]? {
        guard raw.count <= 1_048_576, let text = String(data: raw, encoding: .utf8) else { return nil }
        guard case let .valid(root) = JSONParser.parse(text), case let .object(members) = root.value else {
            return nil
        }
        // JSONParser rejects identical decoded keys. Swift Dictionary also
        // considers canonically equivalent Unicode keys equal, so reject
        // those explicitly rather than trapping during dictionary creation.
        var fields: [String: JSONNode] = [:]
        for member in members {
            guard fields.updateValue(member.value, forKey: member.key) == nil else { return nil }
        }
        return fields
    }

    private static func versionStatus(in fields: [String: JSONNode]) -> Status? {
        guard let version = fields["schemaVersion"] else { return nil }
        guard case let .number(rawVersion) = version.value,
              let number = Double(rawVersion), number.isFinite,
              number.rounded(.towardZero) == number, number >= 1 else { return .malformed }
        return number > 1 ? .unknownFuture : .valid
    }

    private static func validEditor(fields: [String: JSONNode], raw: Data) -> Bool {
        guard let font = fields["font"], case let .object(fontMembers) = font.value,
              Set(fontMembers.map(\.key)).isSubset(of: ["familyName", "size"]) else { return false }
        return (try? JSONDecoder().decode(EditorSettings.self, from: raw)) != nil
    }

    private static func persistedValues(in fields: [String: JSONNode]) -> [Destination: Bool] {
        var persisted: [Destination: Bool] = [:]
        for (key, destination) in destinationKeys {
            if let node = fields[key], case let .boolean(value) = node.value {
                persisted[destination] = value
            }
        }
        return persisted
    }

    var domain: LegacyEditorDestinationDomain {
        switch status {
        case .absent: .absent
        case .knownCompatible, .valid: .valid(persisted: persisted, provenAbsent: provenAbsent)
        case .malformed: .unreadable
        case .unknownFuture: .futureVersion
        }
    }

    private static let destinationKeys: [(String, Destination)] = [
        ("autoIncrementOrderedLists", .autoIncrementOrderedLists),
        ("convertsTabsToSpaces", .convertsTabsToSpaces),
        ("smartHome", .smartHome),
    ]

    private static let editorKeys: Set<String> = [
        "schemaVersion", "font", "wrapsLines", "showsInvisibles", "showsStatusBar",
        "indentationWidth", "assistsEnabled", "continuesMarkdownPrefixes",
        "completesMatchingCharacters", "convertsTabsToSpaces", "smartHome",
        "autoIncrementOrderedLists",
    ]
}
