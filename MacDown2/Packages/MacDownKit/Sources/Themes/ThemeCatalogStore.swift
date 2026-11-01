import Darwin
import Foundation

/// One owner for managed theme files. Filesystem operations run on this actor,
/// never on MainActor, and contain no suspension between baseline and commit.
public actor ThemeCatalogStore {
    let directory: ThemeDirectory
    let identity = UUID()
    let now: @Sendable () -> ContinuousClock.Instant
    var catalog: ThemeCatalogSnapshot
    var records: [UUID: Record] = [:]
    var diagnostics: [ThemeCatalogDiagnostic] = []
    var pending: [UUID: PendingFailure] = [:]
    var observations: [UUID: String] = [:]
    var needsRecheck = false
    var eventObserver: ThemeCatalogEvents?

    struct Record: Sendable, Equatable {
        let file: ThemeFile
        let bytes: ThemeStoredBytes
    }

    struct PendingFailure: Sendable {
        let signature: String
        let firstSeen: ContinuousClock.Instant
    }

    public init(directoryURL: URL) throws {
        directory = try ThemeDirectory(url: directoryURL)
        catalog = try ThemeCatalogSnapshot(revision: 0, customThemes: [])
        now = { ContinuousClock.now }
    }

    init(directoryURL: URL, hooks: ThemeStorageHooks,
         now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) throws {
        directory = try ThemeDirectory(url: directoryURL, hooks: hooks)
        catalog = try ThemeCatalogSnapshot(revision: 0, customThemes: [])
        self.now = now
    }

    init(directory: ThemeDirectory) throws {
        self.directory = directory
        catalog = try ThemeCatalogSnapshot(revision: 0, customThemes: [])
        now = { ContinuousClock.now }
    }

    deinit { eventObserver?.cancel() }

    public func currentState() -> ThemeCatalogState {
        ThemeCatalogState(catalog: catalog, diagnostics: diagnostics, needsRecheck: needsRecheck)
    }

    public func prepareImport(_ data: Data) throws -> PreparedThemeImport {
        try Task.checkCancellation()
        let state = try reload()
        let plan = try ThemeImportPlan(data: data, catalog: state.catalog)
        if case .newTheme = plan.situation,
           try directory.identifiers().count >= ThemeCatalogSnapshot.maximumCustomThemes {
            throw ThemeCatalogError.catalogFull
        }
        let before: ThemeFileFingerprint? = if case let .conflictingIdentity(id, _) = plan.situation {
            records[id]?.bytes.fingerprint
        } else {
            nil
        }
        return PreparedThemeImport(plan: plan, storeID: identity, beforeFile: before)
    }

    public func commitImport(_ prepared: PreparedThemeImport,
                             choice: ThemeImportPlan.Choice) throws -> ThemeCatalogMutation {
        guard prepared.storeID == identity else { throw ThemeCatalogError.invalidImportChoice }
        try Task.checkCancellation()
        _ = try reload()
        let change = try prepared.plan.resolve(choice, against: catalog)
        switch change {
        case let .unchanged(id):
            return ThemeCatalogMutation(state: currentState(), affectedID: id, changed: false, warnings: [])
        case let .install(file):
            // Unreadable managed files still reserve physical catalog slots.
            guard try directory.identifiers().count < ThemeCatalogSnapshot.maximumCustomThemes else {
                throw ThemeCatalogError.catalogFull
            }
            let next = try nextCatalog(inserting: file)
            let publication = try directory.install(file)
            return finish(file: file, publication: publication, next: next)
        case let .replace(file, _):
            guard let before = prepared.beforeFile else { throw ThemeCatalogError.staleImportPlan }
            let next = try nextCatalog(inserting: file)
            let publication = try directory.replace(file, expected: before)
            return finish(file: file, publication: publication, next: next)
        }
    }

    public func prepareDeletion(id: UUID) throws -> PreparedThemeDeletion {
        try Task.checkCancellation()
        _ = try reload()
        guard let record = records[id] else { throw ThemeCatalogError.invalidImportChoice }
        return PreparedThemeDeletion(id: id, storeID: identity, catalogRevision: catalog.revision,
                                     beforeFile: record.bytes.fingerprint)
    }

    public func delete(_ prepared: PreparedThemeDeletion) throws -> ThemeCatalogMutation {
        guard prepared.storeID == identity else { throw ThemeCatalogError.invalidImportChoice }
        try Task.checkCancellation()
        _ = try reload()
        guard prepared.catalogRevision == catalog.revision else { throw ThemeCatalogError.staleImportPlan }
        let next = try nextCatalog(removing: prepared.id)
        let result = try directory.delete(id: prepared.id, expected: prepared.beforeFile)
        records.removeValue(forKey: prepared.id)
        catalog = next
        pending.removeValue(forKey: prepared.id)
        diagnostics.removeAll { $0.id == prepared.id }
        var warnings: [ThemeCatalogWarning] = result.durabilityWarning ? [.durabilityUnconfirmed] : []
        if let name = result.preservedName {
            warnings.append(.retainedStagingFile(name))
        }
        if (try? directory.checkRoot()) == nil {
            warnings.append(.directoryChanged)
        }
        return refreshedMutation(id: prepared.id, warnings: warnings)
    }

    func nextCatalog(inserting file: ThemeFile? = nil, removing id: UUID? = nil) throws -> ThemeCatalogSnapshot {
        guard catalog.revision < UInt64.max - 2 else { throw ThemeCatalogError.staleImportPlan }
        var files = records.mapValues(\.file)
        if let id {
            files.removeValue(forKey: id)
        }
        if let file {
            files[file.stableID] = file
        }
        return try ThemeCatalogSnapshot(revision: catalog.revision + 1, customThemes: Array(files.values))
    }

    private func finish(file: ThemeFile, publication: ThemePublication,
                        next: ThemeCatalogSnapshot) -> ThemeCatalogMutation {
        records[file.stableID] = Record(file: file, bytes: publication.bytes)
        catalog = next
        pending.removeValue(forKey: file.stableID)
        diagnostics.removeAll { $0.id == file.stableID }
        var warnings: [ThemeCatalogWarning] = publication.durabilityWarning ? [.durabilityUnconfirmed] : []
        if let name = publication.preservedStagingName {
            warnings.append(.retainedStagingFile(name))
        }
        if !publication.rootStillCurrent {
            warnings.append(.directoryChanged)
        }
        return refreshedMutation(id: file.stableID, warnings: warnings)
    }

    private func refreshedMutation(id: UUID, warnings: [ThemeCatalogWarning]) -> ThemeCatalogMutation {
        // Publication already happened. A failed refresh is a separate warning,
        // never a thrown "write failed" that would invite a duplicate retry.
        var warnings = warnings
        do {
            _ = try reload()
        } catch {
            warnings.append(.refreshFailed)
        }
        return ThemeCatalogMutation(state: currentState(), affectedID: id, changed: true, warnings: warnings)
    }
}
