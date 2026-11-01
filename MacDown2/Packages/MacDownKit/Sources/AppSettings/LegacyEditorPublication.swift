import Foundation

public extension UserDefaultsAppSettingsStore {
    enum LegacyPublicationFailure: Error, Equatable {
        case invalidPersistenceDomain
        case unavailablePersistenceDomain
        case unboundPersistenceDomain
        case sourceChanged
        case readbackFailed
    }

    enum LegacyPublicationResult: Sendable, Equatable {
        case applied
        case alreadyApplied
        case conflict
    }

    /// Bind ordinary edits and conditional import to the same saved domain.
    /// Fallback search-list values never count as persisted settings here.
    /// The caller still owns durable journaling and obtaining a fresh source.
    init(persistentDomainName name: String) throws {
        guard Self.admitsPersistenceDomain(name) else { throw LegacyPublicationFailure.invalidPersistenceDomain }
        guard let defaults = UserDefaults(suiteName: name) else {
            throw LegacyPublicationFailure.unavailablePersistenceDomain
        }
        self.init(defaults: defaults, persistenceDomainName: name)
    }

    /// Capture only this store's authoritative saved editor value. Generic
    /// injected stores cannot establish which domain their writes would reach.
    func legacyEditorDestination() throws -> EditorStoredDomain {
        guard persistenceDomainName != nil else { throw LegacyPublicationFailure.unboundPersistenceDomain }
        return editorStoredDomain
    }

    /// One serialized in-process write boundary, not a defaults transaction or
    /// a disk-durability guarantee. E17 must prepare its journal before calling.
    /// Readback failure never authorizes restoring over another writer's value.
    func publishLegacyEditorChanges(
        _ proposal: LegacyEditorWriteProposal,
        currentSource: LegacyPreferenceSnapshot
    ) throws -> LegacyPublicationResult {
        switch try proposal.replayDisposition(current: legacyEditorDestination()) {
        case .alreadyApplied: return .alreadyApplied
        case .conflict: return .conflict
        case .readyToWrite: break
        }
        guard currentSource.canonicalDigest == proposal.sourceDigest else {
            throw LegacyPublicationFailure.sourceChanged
        }
        defaults.set(proposal.desiredData, forKey: Key.editor.rawValue)
        guard let persistenceDomainName,
              let saved = defaults.persistentDomain(forName: persistenceDomainName)?[Key.editor.rawValue] as? Data,
              saved == proposal.desiredData
        else { throw LegacyPublicationFailure.readbackFailed }
        return .applied
    }

    private static func admitsPersistenceDomain(_ name: String) -> Bool {
        let normalized = name.lowercased()
        guard name.utf8.count <= 255,
              !normalized.hasPrefix("com.uranusjr.macdown"),
              normalized != "com.apple", !normalized.hasPrefix("com.apple.")
        else { return false }
        let labels = name.utf8.split(separator: 46, omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            guard !label.isEmpty, label.count <= 63, label.first != 45, label.last != 45 else { return false }
            return label.allSatisfy { byte in
                (48 ... 57).contains(byte) || (65 ... 90).contains(byte) || (97 ... 122).contains(byte) || byte == 45
            }
        }
    }
}
