import Foundation

/// The decision shown before any managed theme can be changed.
public struct ThemeImportPlan: Sendable, Equatable {
    public enum Situation: Sendable, Equatable {
        case newTheme
        case alreadyInstalled(id: UUID)
        case conflictingIdentity(id: UUID, beforeCanonicalDigest: String)
    }

    public enum Choice: Sendable {
        case install
        case useExisting
        case replace
        case importCopy
    }

    public enum Change: Sendable, Equatable {
        case unchanged(id: UUID)
        case install(ThemeFile)
        case replace(ThemeFile, beforeCanonicalDigest: String)
    }

    public let incoming: ThemeFile
    public let catalogRevision: UInt64
    public let situation: Situation

    public init(data: Data, catalog: ThemeCatalogSnapshot) throws {
        let incoming = try ThemeFile.decode(data)
        self.incoming = incoming
        catalogRevision = catalog.revision
        if let existing = catalog.customTheme(id: incoming.stableID) {
            situation = try existing.hasSameContent(as: incoming)
                ? .alreadyInstalled(id: existing.stableID)
                : .conflictingIdentity(id: existing.stableID, beforeCanonicalDigest: existing.canonicalDigest())
        } else if let identical = catalog.customThemes.first(where: { $0.hasSameContent(as: incoming) }) {
            situation = .alreadyInstalled(id: identical.stableID)
        } else {
            guard catalog.customThemes.count < ThemeCatalogSnapshot.maximumCustomThemes else {
                throw ThemeCatalogError.catalogFull
            }
            situation = .newTheme
        }
    }

    /// Resolve an explicit choice against a fresh catalog. This proposes a
    /// change only; it neither writes files nor confirms on-disk byte identity.
    public func resolve(
        _ choice: Choice,
        against catalog: ThemeCatalogSnapshot,
        generatedID: UUID = UUID()
    ) throws -> Change {
        guard catalog.revision == catalogRevision else { throw ThemeCatalogError.staleImportPlan }
        switch (situation, choice) {
        case let (.alreadyInstalled(id), .useExisting):
            guard let existing = catalog.customTheme(id: id), existing.hasSameContent(as: incoming) else {
                throw ThemeCatalogError.staleImportPlan
            }
            return .unchanged(id: id)
        case let (.conflictingIdentity(id, digest), .replace):
            guard let existing = catalog.customTheme(id: id), try existing.canonicalDigest() == digest else {
                throw ThemeCatalogError.staleImportPlan
            }
            let replacement = try ThemeFile(theme: incoming.theme, stableID: id)
            return .replace(replacement, beforeCanonicalDigest: digest)
        case (.newTheme, .install), (_, .importCopy):
            guard catalog.customThemes.count < ThemeCatalogSnapshot.maximumCustomThemes else {
                throw ThemeCatalogError.catalogFull
            }
            guard catalog.customTheme(id: generatedID) == nil, generatedID != incoming.stableID else {
                throw ThemeCatalogError.generatedIdentityCollision
            }
            return try .install(ThemeFile(theme: incoming.theme, stableID: generatedID))
        default:
            throw ThemeCatalogError.invalidImportChoice
        }
    }
}
