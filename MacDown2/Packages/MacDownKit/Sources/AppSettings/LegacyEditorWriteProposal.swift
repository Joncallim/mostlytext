import CryptoKit
import Foundation

/// Bytes prepared for E17's serialized, journaled writer. Creating a proposal
/// never reads or writes preferences. Consent names exact destination fields;
/// it does not authorize replacing an unreadable domain.
public struct LegacyEditorWriteProposal: Sendable, Equatable {
    public typealias Destination = LegacyImportPlan.Destination
    public typealias StoredDomain = UserDefaultsAppSettingsStore.EditorStoredDomain

    public enum Failure: Error, Equatable {
        case stalePlan
        case unavailableDestination
        case noSelectedChanges
        case unproposedSelection
        case replacementConsentRequired
    }

    public let sourceDigest: String
    public let mappingVersion: Int
    public let fontPostScriptName: String?
    public let beforeRevision: String
    public let desiredRevision: String
    public let desiredData: Data
    public let selected: Set<Destination>

    /// Revalidate source and raw destination after consent. Existing values,
    /// including defaults, need explicit replacement consent for each field.
    public init(
        plan: LegacyImportPlan,
        source: LegacyPreferenceSnapshot,
        storedDestination: StoredDomain,
        selected: Set<Destination>,
        replacing: Set<Destination> = [],
        font: LegacyResolvedFont? = nil,
        replacingFont: Bool = false
    ) throws {
        guard case let .decoded(destination) = storedDestination else { throw Failure.unavailableDestination }
        guard plan.matches(source: source, destination: destination) else { throw Failure.stalePlan }
        guard destination.status == .absent || destination.settings != nil else {
            throw Failure.unavailableDestination
        }
        guard !selected.isEmpty || font != nil else { throw Failure.noSelectedChanges }
        guard replacing.isSubset(of: selected) else { throw Failure.unproposedSelection }
        let proposed = Set(plan.entries.map(\.destination))
        guard selected.isSubset(of: proposed) else { throw Failure.unproposedSelection }
        if let font {
            guard font.matches(source) else { throw Failure.stalePlan }
            guard destination.status == .absent || replacingFont else { throw Failure.replacementConsentRequired }
        }
        var settings = destination.settings ?? .default
        if let font {
            settings.font = font.descriptor
        }
        try Self.apply(plan: plan, selected: selected, replacing: replacing, to: &settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(settings)
        mappingVersion = font == nil ? 1 : 2
        fontPostScriptName = font?.postScriptName
        sourceDigest = source.canonicalDigest
        beforeRevision = destination.rawRevision
        desiredRevision = Self.revision(data)
        desiredData = data
        self.selected = selected
    }

    public enum ReplayDisposition: Sendable, Equatable {
        case readyToWrite
        case alreadyApplied
        case conflict
    }

    /// A third value belongs to a later edit and must survive recovery. The
    /// writer must capture non-Data values as conflicts, never as absence.
    public func replayDisposition(current stored: StoredDomain) -> ReplayDisposition {
        guard case let .decoded(current) = stored else { return .conflict }
        if current.rawRevision == desiredRevision {
            return .alreadyApplied
        }
        return current.rawRevision == beforeRevision ? .readyToWrite : .conflict
    }

    private static func apply(
        plan: LegacyImportPlan,
        selected: Set<Destination>,
        replacing: Set<Destination>,
        to settings: inout EditorSettings
    ) throws {
        for entry in plan.entries where selected.contains(entry.destination) {
            let value: Bool
            switch entry.disposition {
            case let .fillProvenAbsent(suggested): value = suggested
            case let .retainPersisted(_, suggested):
                guard replacing.contains(entry.destination) else { throw Failure.replacementConsentRequired }
                value = suggested
            case .blockedUnreadable, .blockedFutureVersion, .blockedUnknownPresence:
                throw Failure.unavailableDestination
            }
            switch entry.destination {
            case .autoIncrementOrderedLists: settings.autoIncrementOrderedLists = value
            case .convertsTabsToSpaces: settings.convertsTabsToSpaces = value
            case .smartHome: settings.smartHome = value
            }
        }
    }

    private static func revision(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
