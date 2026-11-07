public enum LegacyMigrationFailure: Error, Sendable, Equatable {
    case unsafeStorage
    case changedStorage
    case unavailable(Int32)
    case invalidRecord
    case transactionExists
    case invalidPhase
    case unboundDestination
    case busy
}
