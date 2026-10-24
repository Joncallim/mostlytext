import Foundation

/// Internal form of decoder-produced destination evidence. An import caller
/// cannot assert that an in-memory default represents an absent stored value.
enum LegacyEditorDestinationDomain: Sendable, Equatable {
    case absent
    case valid(persisted: [LegacyEditorBooleanConversion.Destination: Bool],
               provenAbsent: Set<LegacyEditorBooleanConversion.Destination>)
    case unreadable
    case futureVersion
}

public struct LegacyImportPlan: Sendable, Equatable {
    public typealias Destination = LegacyEditorBooleanConversion.Destination

    public enum Disposition: Sendable, Equatable {
        case fillProvenAbsent(Bool)
        case retainPersisted(Bool, suggested: Bool)
        case blockedUnreadable
        case blockedFutureVersion
        case blockedUnknownPresence
    }

    public struct Entry: Sendable, Equatable {
        public let destination: Destination
        public let disposition: Disposition
    }

    public let sourceDigest: String
    public let destinationRevision: String
    public let entries: [Entry]
    public let invalidSourceKeys: [String]

    public init(source: LegacyPreferenceSnapshot, destination: LegacyEditorDestinationEvidence) {
        let conversion = LegacyEditorBooleanConversion(snapshot: source)
        sourceDigest = source.canonicalDigest
        destinationRevision = destination.rawRevision
        invalidSourceKeys = conversion.invalidSourceKeys
        entries = conversion.proposedValues.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { key in
            guard let suggested = conversion.proposedValues[key] else { return nil }
            return Entry(
                destination: key,
                disposition: Self.classify(key, suggested: suggested, in: destination.domain)
            )
        }
    }

    /// Only these suggestions are eligible for a default import. This is a
    /// preview, not an authorization to write: the serialized executor must
    /// revalidate both source and destination revision at its write boundary.
    public var defaultFills: [Destination: Bool] {
        entries.reduce(into: [:]) { fills, entry in
            if case let .fillProvenAbsent(value) = entry.disposition {
                fills[entry.destination] = value
            }
        }
    }

    public func matches(source: LegacyPreferenceSnapshot, destination: LegacyEditorDestinationEvidence) -> Bool {
        source.canonicalDigest == sourceDigest && destination.rawRevision == destinationRevision
    }

    private static func classify(
        _ key: Destination,
        suggested: Bool,
        in domain: LegacyEditorDestinationDomain
    ) -> Disposition {
        switch domain {
        case .absent:
            return .fillProvenAbsent(suggested)
        case let .valid(persisted, provenAbsent):
            if let current = persisted[key] {
                return .retainPersisted(current, suggested: suggested)
            }
            return provenAbsent.contains(key) ? .fillProvenAbsent(suggested) : .blockedUnknownPresence
        case .unreadable:
            return .blockedUnreadable
        case .futureVersion:
            return .blockedFutureVersion
        }
    }
}
