import Foundation

/// Property-list bytes cross actors; UserDefaults objects stay on MainActor.
public struct InstallationPreferences: Sendable {
    public let application: Data?
    public let workspace: Data?

    public init(application: [String: Any]?, workspace: [String: Any]?) throws {
        self.application = try Self.encode(application)
        self.workspace = try Self.encode(workspace)
    }

    init(application: Data?, workspace: Data?) throws {
        _ = try Self.digest(application); _ = try Self.digest(workspace)
        self.application = application; self.workspace = workspace
    }

    var populated: Bool {
        application != nil || workspace != nil
    }

    public var digests: [String] {
        get throws { try [Self.digest(application), Self.digest(workspace)] }
    }

    static func encode(_ domain: [String: Any]?) throws -> Data? {
        guard let domain, !domain.isEmpty else { return nil }
        _ = try LegacyPreferenceSnapshot(domain: domain)
        let bytes = try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0)
        guard bytes.count <= LegacyPreferenceSnapshot.maximumBytes else { throw LegacyPreferenceSnapshotError.tooLarge }
        return bytes
    }

    public static func decode(_ bytes: Data?) throws -> [String: Any]? {
        guard let bytes else { return nil }
        guard bytes.count <= LegacyPreferenceSnapshot.maximumBytes,
              let domain = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any]
        else { throw LegacyMigrationFailure.invalidRecord }
        _ = try LegacyPreferenceSnapshot(domain: domain)
        return domain.isEmpty ? nil : domain
    }

    static func digest(_ bytes: Data?) throws -> String {
        guard let domain = try decode(bytes) else { return "absent" }
        return try LegacyPreferenceSnapshot(domain: domain).canonicalDigest
    }
}

/// Serialized conditional whole-domain publication into the new namespace.
/// Before/desired comparisons and readback have no intervening await.
@MainActor
public struct InstallationPreferencesPublisher {
    private let domains: [String]
    private let defaults: UserDefaults
    var afterDomain: ((Int) throws -> Void)?

    public init(applicationDomain: String = ApplicationStorageLocations.applicationDomain,
                workspaceDomain: String = ApplicationStorageLocations.workspaceDomain) throws {
        guard UserDefaultsAppSettingsStore.admitsPersistenceDomain(applicationDomain),
              UserDefaultsAppSettingsStore.admitsPersistenceDomain(workspaceDomain),
              applicationDomain != workspaceDomain,
              ![ApplicationStorageLocations.developmentDomain, ApplicationStorageLocations.developmentWorkspaceDomain]
              .contains(applicationDomain),
              ![ApplicationStorageLocations.developmentDomain, ApplicationStorageLocations.developmentWorkspaceDomain]
              .contains(workspaceDomain) else { throw LegacyMigrationFailure.unboundDestination }
        domains = [applicationDomain, workspaceDomain]
        defaults = .standard
    }

    public func snapshot() throws -> InstallationPreferences {
        try InstallationPreferences(application: defaults.persistentDomain(forName: domains[0]),
                                    workspace: defaults.persistentDomain(forName: domains[1]))
    }

    public func publish(desired: InstallationPreferences, before: [String],
                        revalidateSource: () throws -> Void) throws {
        guard before.count == 2 else { throw LegacyMigrationFailure.invalidRecord }
        let wanted = try desired.digests
        let current = try snapshot().digests
        guard zip(current.indices, current).allSatisfy({ wanted[$0.0] == $0.1 || before[$0.0] == $0.1 }) else {
            throw LegacyMigrationFailure.transactionExists
        }
        if current != wanted {
            try revalidateSource()
        }
        for (index, bytes) in [desired.application, desired.workspace].enumerated() {
            let now = try snapshot().digests[index]
            if now == wanted[index] {
                continue
            }
            guard now == before[index] else { throw LegacyMigrationFailure.transactionExists }
            if let value = try InstallationPreferences.decode(bytes) {
                defaults.setPersistentDomain(value, forName: domains[index])
            } else {
                // Absence never authorizes deleting a newly populated domain.
                guard now == "absent" else { throw LegacyMigrationFailure.transactionExists }
            }
            guard try snapshot().digests[index] == wanted[index] else {
                throw UserDefaultsAppSettingsStore.LegacyPublicationFailure.readbackFailed
            }
            try afterDomain?(index)
        }
    }
}
