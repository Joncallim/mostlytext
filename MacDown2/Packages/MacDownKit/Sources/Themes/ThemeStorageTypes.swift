import Foundation

public enum ThemeStorageError: Error, Sendable, Equatable {
    case invalidDirectory
    case unsupportedAtomicPublication
    case directoryChanged
    case tooManyDirectoryEntries
    case unsafeFile
    case fileTooLarge
    case changedDuringRead
    case staleFile
    case unavailable(Int32)
    case recoveryRequired(fileName: String)
}

struct ThemeStoredBytes: Sendable, Equatable {
    let bytes: Data
    let fingerprint: ThemeFileFingerprint
}

struct ThemeFileFingerprint: Sendable, Equatable {
    let device: Int64
    let inode: UInt64
    let byteCount: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
    let digest: String
}

struct ThemePublication: Sendable {
    let bytes: ThemeStoredBytes
    let durabilityWarning: Bool
    let preservedStagingName: String?
    let rootStillCurrent: Bool
}

struct ThemeStorageHooks: Sendable {
    var afterReadChunk: (@Sendable (Int) throws -> Void)?
    var beforeExchange: (@Sendable () throws -> Void)?
    var afterExchange: (@Sendable () throws -> Void)?
    var beforeRollback: (@Sendable () throws -> Void)?
    var flush: (@Sendable (Int32) -> Int32)?

    static let none = ThemeStorageHooks()
}

extension ThemeFileFingerprint {
    /// Rename/exchange can update ctime. Verify identity, bytes and mtime
    /// without mistaking that transaction metadata change for an outside edit.
    func matchesMovedObject(_ other: Self) -> Bool {
        device == other.device && inode == other.inode && byteCount == other.byteCount
            && modifiedSeconds == other.modifiedSeconds && modifiedNanoseconds == other.modifiedNanoseconds
            && digest == other.digest
    }
}

public struct ThemeCatalogDiagnostic: Sendable, Equatable, Identifiable {
    public enum Problem: Sendable, Equatable {
        case missingFile
        case unreadableFile
        case invalidTheme
        case catalogFull
    }

    public let id: UUID
    public let problem: Problem
    public let pendingConfirmation: Bool
}

public struct ThemeCatalogState: Sendable, Equatable {
    public let catalog: ThemeCatalogSnapshot
    public let diagnostics: [ThemeCatalogDiagnostic]
    public let needsRecheck: Bool
}

public struct PreparedThemeImport: Sendable {
    public let plan: ThemeImportPlan
    let storeID: UUID
    let beforeFile: ThemeFileFingerprint?
}

public struct PreparedThemeDeletion: Sendable {
    public let id: UUID
    let storeID: UUID
    let catalogRevision: UInt64
    let beforeFile: ThemeFileFingerprint
}

public enum ThemeCatalogWarning: Sendable, Equatable {
    case durabilityUnconfirmed
    case retainedStagingFile(String)
    case directoryChanged
    case refreshFailed
}

public struct ThemeCatalogMutation: Sendable {
    public let state: ThemeCatalogState
    public let affectedID: UUID
    public let changed: Bool
    public let warnings: [ThemeCatalogWarning]
}
