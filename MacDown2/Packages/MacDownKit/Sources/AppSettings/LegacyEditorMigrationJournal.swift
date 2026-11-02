import Foundation

public enum LegacyEditorMigrationPhase: String, Sendable, Equatable {
    case empty, prepared, acknowledged, complete
}

/// Owns one retained consent transaction. Filesystem work has one actor owner;
/// the original app and ordinary preferences are never accessed by this actor.
public actor LegacyEditorMigrationJournal {
    private let directory: MigrationJournalDirectory

    public init(directoryURL: URL) throws {
        directory = try MigrationJournalDirectory(url: directoryURL)
    }

    init(directoryURL: URL,
         checkpoint: @escaping @Sendable (MigrationJournalDirectory.Checkpoint) throws -> Void) throws {
        directory = try MigrationJournalDirectory(url: directoryURL, checkpoint: checkpoint)
    }

    public func close() {
        directory.close()
    }

    public func inspect() throws -> LegacyEditorMigrationPhase {
        try load().phase
    }

    struct Snapshot: Sendable {
        let plan: LegacyEditorJournalPlan?
        let phase: LegacyEditorMigrationPhase
    }

    func load() throws -> Snapshot {
        let planData = try directory.read("plan.json")
        let ack = try directory.read("acknowledged.json")
        let complete = try directory.read("complete.json")
        guard let planData else {
            guard ack == nil, complete == nil else { throw LegacyMigrationFailure.invalidRecord }
            return Snapshot(plan: nil, phase: .empty)
        }
        let plan = try LegacyEditorJournalPlan.decode(planData)
        if let ack {
            try validateMarker(ack, plan: planData, phase: .acknowledged)
        }
        if let complete {
            guard ack != nil else { throw LegacyMigrationFailure.invalidRecord }
            try validateMarker(complete, plan: planData, phase: .complete)
        }
        return Snapshot(plan: plan, phase: complete != nil ? .complete : ack != nil ? .acknowledged : .prepared)
    }

    func prepare(_ plan: LegacyEditorJournalPlan) throws -> Snapshot {
        let state = try load()
        if let existing = state.plan {
            guard existing == plan else { throw LegacyMigrationFailure.transactionExists }
        }
        // Resync identical records too: a prior attempt may have published
        // before failing its final directory sync.
        try directory.publish(plan.encoded(), as: "plan.json")
        let after = try load()
        guard after.plan == plan else { throw LegacyMigrationFailure.changedStorage }
        return after
    }

    func acknowledge(_ plan: LegacyEditorJournalPlan) throws {
        let state = try load()
        guard state.plan == plan else { throw LegacyMigrationFailure.transactionExists }
        try directory.publish(marker(plan: plan, phase: .acknowledged), as: "acknowledged.json")
    }

    func complete(_ plan: LegacyEditorJournalPlan) throws {
        let state = try load()
        guard state.plan == plan else { throw LegacyMigrationFailure.transactionExists }
        guard state.phase == .acknowledged || state.phase == .complete else {
            throw LegacyMigrationFailure.invalidPhase
        }
        try directory.publish(marker(plan: plan, phase: .complete), as: "complete.json")
    }

    private struct Marker: Codable {
        let version: Int
        let planDigest: String
        let phase: String
    }

    private func marker(plan: LegacyEditorJournalPlan, phase: LegacyEditorMigrationPhase) throws -> Data {
        let value = try Marker(
            version: 1,
            planDigest: LegacyEditorJournalPlan.digest(plan.encoded()),
            phase: phase.rawValue
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func validateMarker(_ bytes: Data, plan: Data, phase: LegacyEditorMigrationPhase) throws {
        guard bytes.count <= 512 else { throw LegacyMigrationFailure.invalidRecord }
        try LegacyEditorJournalPlan.validateJSON(bytes)
        let decoded = try JSONDecoder().decode(Marker.self, from: bytes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard decoded.version == 1, decoded.phase == phase.rawValue,
              decoded.planDigest == LegacyEditorJournalPlan.digest(plan),
              try encoder.encode(decoded) == bytes else { throw LegacyMigrationFailure.invalidRecord }
    }
}
