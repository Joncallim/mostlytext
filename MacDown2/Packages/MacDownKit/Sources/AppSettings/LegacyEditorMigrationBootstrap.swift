import Foundation

/// Runs the optional editor import before its host exposes mutable settings.
/// A conflict is reported for review; it never authorizes a destructive reset.
@MainActor
public final class LegacyEditorMigrationBootstrap {
    public enum State: Sendable, Equatable {
        case inspecting, preparing, publishing, recording, ready, conflict, recoveryRequired
    }

    public enum Outcome: Sendable, Equatable {
        case noPendingTransaction, applied, alreadyApplied, alreadyCompleted, conflict
    }

    public private(set) var state = State.inspecting
    private let store: UserDefaultsAppSettingsStore
    private let journal: LegacyEditorMigrationJournal
    private var running = false
    var afterPreparation: (@MainActor () async throws -> Void)?

    public init(store: UserDefaultsAppSettingsStore, journal: LegacyEditorMigrationJournal) throws {
        guard store.persistenceDomainName != nil else { throw LegacyMigrationFailure.unboundDestination }
        self.store = store; self.journal = journal
    }

    public var resolveFont: (@MainActor (LegacyPreferenceReport.FontRequest) -> LegacyResolvedFont?)?

    public func start(_ proposal: LegacyEditorWriteProposal,
                      currentSource: @MainActor () throws -> LegacyPreferenceSnapshot) async throws -> Outcome {
        try await run(proposal: proposal, currentSource: currentSource)
    }

    public func resume(currentSource: @MainActor () throws -> LegacyPreferenceSnapshot) async throws -> Outcome {
        try await run(proposal: nil, currentSource: currentSource)
    }

    private func run(proposal: LegacyEditorWriteProposal?,
                     currentSource: @MainActor () throws -> LegacyPreferenceSnapshot) async throws -> Outcome {
        guard !running else { throw LegacyMigrationFailure.busy }
        running = true
        defer { running = false }
        state = .inspecting
        do {
            try Task.checkCancellation()
            guard let snapshot = try await prepareIfNeeded(proposal) else {
                state = .conflict; return .conflict
            }
            guard let plan = snapshot.plan else { state = .ready; return .noPendingTransaction }
            guard plan.domain == store.persistenceDomainName else { throw LegacyMigrationFailure.unboundDestination }
            let restored = try plan.restoredProposal()
            if let proposal, proposal != restored {
                throw LegacyMigrationFailure.transactionExists
            }
            return try await recover(plan, phase: snapshot.phase, proposal: restored, currentSource: currentSource)
        } catch {
            state = .recoveryRequired
            throw error
        }
    }

    private func prepareIfNeeded(_ proposal: LegacyEditorWriteProposal?) async throws
        -> LegacyEditorMigrationJournal.Snapshot? {
        let snapshot = try await journal.load()
        guard snapshot.plan == nil, let proposal else { return snapshot }
        guard try proposal.replayDisposition(current: store.legacyEditorDestination()) != .conflict else { return nil }
        guard let domain = store.persistenceDomainName else { throw LegacyMigrationFailure.unboundDestination }
        let raw = store.defaults.persistentDomain(forName: domain)?[UserDefaultsAppSettingsStore.Key.editor.rawValue]
        if raw != nil, !(raw is Data) {
            return nil
        }
        let plan = try LegacyEditorJournalPlan(proposal: proposal, domain: domain, before: raw as? Data)
        state = .preparing
        return try await journal.prepare(plan)
    }

    private func recover(_ plan: LegacyEditorJournalPlan, phase: LegacyEditorMigrationPhase,
                         proposal: LegacyEditorWriteProposal,
                         currentSource: @MainActor () throws -> LegacyPreferenceSnapshot) async throws -> Outcome {
        if phase == .complete {
            state = .ready; return .alreadyCompleted
        }
        if phase == .acknowledged {
            // The readback is historical proof. Preserve any later edit/revert.
            return try await finish(plan, result: .alreadyApplied)
        }
        // A crash may have interrupted the final directory sync of the plan.
        _ = try await journal.prepare(plan)
        try await afterPreparation?()
        try Task.checkCancellation()
        state = .publishing
        let result = try publish(proposal, currentSource: currentSource)
        if result == .conflict {
            state = .conflict; return .conflict
        }
        return try await finish(plan, result: result)
    }

    private func publish(_ proposal: LegacyEditorWriteProposal,
                         currentSource: @MainActor () throws -> LegacyPreferenceSnapshot) throws
        -> UserDefaultsAppSettingsStore.LegacyPublicationResult {
        switch try proposal.replayDisposition(current: store.legacyEditorDestination()) {
        case .conflict: return .conflict
        case .alreadyApplied: return .alreadyApplied
        case .readyToWrite:
            let source = try currentSource()
            guard proposal.matchesJournalSource(source), fontStillMatches(proposal, source: source) else {
                throw UserDefaultsAppSettingsStore.LegacyPublicationFailure.sourceChanged
            }
            return try store.publishLegacyEditorChanges(proposal, currentSource: source)
        }
    }

    private func fontStillMatches(_ proposal: LegacyEditorWriteProposal, source: LegacyPreferenceSnapshot) -> Bool {
        guard let name = proposal.fontPostScriptName else { return true }
        guard let desired = LegacyEditorDestinationEvidence.decode(proposal.desiredData).settings else { return false }
        for entry in LegacyPreferenceReport(snapshot: source).entries {
            if case let .requiresExactInstalledFont(request) = entry.disposition,
               request.postScriptName.utf8.elementsEqual(name.utf8) {
                guard let actual = resolveFont?(request)?.descriptor else { return false }
                return actual.familyName.utf8.elementsEqual(desired.font.familyName.utf8)
                    && actual.size == desired.font.size
            }
        }
        return false
    }

    private func finish(_ plan: LegacyEditorJournalPlan,
                        result: UserDefaultsAppSettingsStore.LegacyPublicationResult) async throws -> Outcome {
        // After readback, record the acknowledged operation even if cancelled.
        state = .recording
        try await journal.acknowledge(plan)
        try await journal.complete(plan)
        state = .ready
        return result == .applied ? .applied : .alreadyApplied
    }
}
