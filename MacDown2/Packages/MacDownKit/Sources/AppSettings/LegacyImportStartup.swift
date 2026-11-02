import Foundation
import Observation

/// Owns the optional import before mutable application models exist. Every
/// transition to ready releases the journal lock before notifying the host.
@MainActor
@Observable
public final class LegacyImportStartup {
    public enum Phase: Sendable, Equatable { case inspecting, review, running, blocked, ready }

    public struct Review: Sendable {
        public let source: LegacyPreferenceSnapshot
        public let plan: LegacyImportPlan
        public let font: LegacyResolvedFont?
        public let replacesSavedEditor: Bool
        public let unavailableFontName: String?
    }

    public private(set) var phase: Phase
    public private(set) var review: Review?
    /// No ordinary model exists in these states and no import write is in
    /// flight, so Quit can leave the prior session/recovery untouched.
    public var canQuitWithoutSession: Bool {
        phase == .review || phase == .blocked
    }

    public var didBecomeReady: (@MainActor () -> Void)?
    private let store: UserDefaultsAppSettingsStore
    private let makeJournal: @Sendable () async throws -> LegacyEditorMigrationJournal
    private let source: @MainActor () throws -> LegacyPreferenceSnapshot
    private let resolveFont: @MainActor (LegacyPreferenceReport.FontRequest) -> LegacyResolvedFont?
    private var journal: LegacyEditorMigrationJournal?
    private var bootstrap: LegacyEditorMigrationBootstrap?
    private var began = false

    public init(store: UserDefaultsAppSettingsStore, disabled: Bool = false,
                makeJournal: @escaping @Sendable () async throws -> LegacyEditorMigrationJournal,
                source: @escaping @MainActor () throws -> LegacyPreferenceSnapshot,
                resolveFont: @escaping @MainActor (LegacyPreferenceReport.FontRequest) -> LegacyResolvedFont?) {
        self.store = store; self.makeJournal = makeJournal; self.source = source; self.resolveFont = resolveFont
        phase = disabled ? .ready : .inspecting
    }

    public func begin() async {
        guard !began, phase == .inspecting else { return }
        began = true
        do {
            let journal = try await makeJournal()
            self.journal = journal
            let bootstrap = try LegacyEditorMigrationBootstrap(store: store, journal: journal)
            bootstrap.resolveFont = resolveFont
            self.bootstrap = bootstrap
            let result = try await bootstrap.resume(currentSource: source)
            guard result != .conflict else { phase = .blocked; return }
            guard result == .noPendingTransaction else { await finish(); return }
            let snapshot = try source()
            guard !snapshot.values.isEmpty, !store.hasDismissedLegacyImport(snapshot.canonicalDigest) else {
                await finish(); return
            }
            guard case let .decoded(destination) = try store.legacyEditorDestination(),
                  destination.status == .absent || destination.settings != nil else { phase = .blocked; return }
            let font = LegacyPreferenceReport(snapshot: snapshot).entries.compactMap { entry -> LegacyResolvedFont? in
                guard case let .requiresExactInstalledFont(request) = entry.disposition else { return nil }
                return resolveFont(request)
            }.first
            let requestedFont = LegacyPreferenceReport(snapshot: snapshot).entries.compactMap { entry -> String? in
                guard case let .requiresExactInstalledFont(request) = entry.disposition else { return nil }
                return request.postScriptName
            }.first
            review = Review(source: snapshot, plan: LegacyImportPlan(source: snapshot, destination: destination),
                            font: font, replacesSavedEditor: destination.status != .absent,
                            unavailableFontName: font == nil ? requestedFont : nil)
            phase = .review
        } catch { phase = .blocked }
    }

    /// Selection is explicit even for absent fields. A selected saved field
    /// means the host presented its per-field replacement consent.
    public func apply(selected: Set<LegacyImportPlan.Destination>, includeFont: Bool) async {
        guard phase == .review, let review, let bootstrap else { return }
        phase = .running
        do {
            guard !includeFont || review.font != nil
            else { throw LegacyEditorWriteProposal.Failure.unproposedSelection }
            let proposal = try LegacyEditorWriteProposal(
                plan: review.plan, source: source(), storedDestination: store.legacyEditorDestination(),
                selected: selected, replacing: selected, font: includeFont ? review.font : nil,
                replacingFont: includeFont
            )
            guard try await bootstrap.start(proposal, currentSource: source) != .conflict else {
                phase = .blocked; return
            }
            await finish()
        } catch { phase = .blocked }
    }

    public func continueWithoutImporting() async {
        guard phase == .review || phase == .blocked else { return }
        let wasReview = phase == .review
        phase = .running
        do {
            if wasReview, let review {
                try store.dismissLegacyImport(review.source.canonicalDigest)
            }
            await finish()
        } catch { phase = .blocked }
    }

    private func finish() async {
        await journal?.close()
        journal = nil; bootstrap = nil
        phase = .ready
        didBecomeReady?()
    }
}

extension UserDefaultsAppSettingsStore {
    private static let importDismissalKey = "legacyImport.dismissedSourceDigest"

    func hasDismissedLegacyImport(_ digest: String) -> Bool {
        guard let persistenceDomainName else { return false }
        return defaults.persistentDomain(forName: persistenceDomainName)?[Self.importDismissalKey] as? String == digest
    }

    func dismissLegacyImport(_ digest: String) throws {
        guard let persistenceDomainName else { throw LegacyPublicationFailure.unboundPersistenceDomain }
        let key = Self.importDismissalKey
        if let current = defaults.persistentDomain(forName: persistenceDomainName)?[key] {
            guard let current = current as? String, current.utf8.count == 64,
                  current.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 102).contains($0) }) else {
                throw LegacyMigrationFailure.invalidRecord
            }
        }
        defaults.set(digest, forKey: key)
        guard defaults.persistentDomain(forName: persistenceDomainName)?[key] as? String == digest else {
            throw LegacyPublicationFailure.readbackFailed
        }
    }
}
