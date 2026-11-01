import CryptoKit
import Foundation

public enum ThemeCatalogError: Error, Sendable, Equatable {
    case catalogFull
    case duplicateIdentity
    case staleImportPlan
    case invalidImportChoice
    case generatedIdentityCollision
}

/// An immutable catalog revision. The persistent store owns revision ordering;
/// callers cannot use a snapshot to authorize an unchecked filesystem write.
public struct ThemeCatalogSnapshot: Sendable, Equatable {
    public static let maximumCustomThemes = 256
    public let revision: UInt64
    public let customThemes: [ThemeFile]

    public init(revision: UInt64, customThemes: [ThemeFile]) throws {
        guard customThemes.count <= Self.maximumCustomThemes else { throw ThemeCatalogError.catalogFull }
        guard Set(customThemes.map(\.stableID)).count == customThemes.count else {
            throw ThemeCatalogError.duplicateIdentity
        }
        self.revision = revision
        self.customThemes = customThemes.sorted { $0.stableID.uuidString < $1.stableID.uuidString }
    }

    public var available: [Theme] {
        BundledThemes.all + customThemes.map(\.theme)
    }

    public func customTheme(id: UUID) -> ThemeFile? {
        customThemes.first { $0.stableID == id }
    }
}

extension ThemeFile {
    /// Hash canonical bytes, not import formatting. The writer must retain a
    /// separate digest of the actual destination bytes for publication checks.
    public func canonicalDigest() throws -> String {
        try SHA256.hash(data: encoded()).map { String(format: "%02x", $0) }.joined()
    }

    func hasSameContent(as other: ThemeFile) -> Bool {
        displayName == other.displayName && appearance == other.appearance
            && chrome == other.chrome && tokenStyles == other.tokenStyles
    }
}
