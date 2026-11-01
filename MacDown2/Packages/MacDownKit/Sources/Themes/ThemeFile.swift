import Foundation

public enum ThemeFileError: Error, Sendable, Equatable {
    case fileTooLarge
    case invalidJSON
    case duplicateKey(String)
    case excessiveNesting
    case unsupportedVersion
    case invalidField(String)
    case tooManyTokenStyles
}

/// The versioned external representation of a custom theme. Decode untrusted
/// bytes through `decode`; there is no public unchecked Decodable initializer.
public struct ThemeFile: Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let maximumFileBytes = 64 * 1024
    public static let maximumTokenStyles = 512
    public let stableID: UUID
    public let displayName: String
    public let appearance: ThemeAppearance
    public let chrome: EditorChrome
    public let tokenStyles: [String: TokenStyle]

    public init(theme: Theme, stableID: UUID = UUID()) throws {
        self.stableID = stableID
        displayName = theme.name
        appearance = theme.appearance
        chrome = theme.chrome
        tokenStyles = theme.tokenStyles
        try ThemeFileValidation.validate(self)
        _ = try encoded()
    }

    public var theme: Theme {
        Theme(id: stableID.uuidString.lowercased(), name: displayName, appearance: appearance,
              chrome: chrome, tokenStyles: tokenStyles)
    }

    public static func decode(_ data: Data) throws -> ThemeFile {
        guard data.count <= maximumFileBytes else { throw ThemeFileError.fileTooLarge }
        try StrictThemeJSON.check(data)
        try ThemeFileValidation.validateStructure(data)
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch let error as DecodingError {
            throw ThemeFileError.invalidField(fieldPath(error))
        } catch {
            throw ThemeFileError.invalidJSON
        }
        return try ThemeFile(
            theme: Theme(id: envelope.stableID.uuidString.lowercased(), name: envelope.displayName,
                         appearance: envelope.appearance, chrome: envelope.chrome, tokenStyles: envelope.tokenStyles),
            stableID: envelope.stableID
        )
    }

    /// Compact, deterministic output keeps the same byte ceiling for import
    /// and export; formatting whitespace is not part of a theme's identity.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(
            schemaVersion: Self.currentSchemaVersion, stableID: stableID, displayName: displayName,
            appearance: appearance, chrome: chrome, tokenStyles: tokenStyles
        ))
        guard data.count <= Self.maximumFileBytes else { throw ThemeFileError.fileTooLarge }
        return data
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let stableID: UUID
        let displayName: String
        let appearance: ThemeAppearance
        let chrome: EditorChrome
        let tokenStyles: [String: TokenStyle]
    }

    private static func fieldPath(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case let .dataCorrupted(value), let .keyNotFound(_, value),
             let .typeMismatch(_, value), let .valueNotFound(_, value):
            context = value
        @unknown default:
            return "theme"
        }
        return context.codingPath.map(\.stringValue).joined(separator: ".")
    }
}
