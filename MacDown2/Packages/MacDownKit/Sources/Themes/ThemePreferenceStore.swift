import Foundation

/// Persists which light/dark theme the user picked.
public protocol ThemePreferenceStoring: Sendable {
    var hasUnreadablePreferences: Bool { get }
    func loadSelection() -> (lightID: String, darkID: String)?
    func saveSelection(lightID: String, darkID: String)
    func loadAppearanceMode() -> ThemeAppearanceMode?
    func saveAppearanceMode(_ mode: ThemeAppearanceMode)
}

public extension ThemePreferenceStoring {
    var hasUnreadablePreferences: Bool {
        false
    }
}

/// `UserDefaults`-backed preference store. Uses an optional suite name so tests
/// can isolate writes to a temp-directory suite.
public struct UserDefaultsThemePreferenceStore: ThemePreferenceStoring {
    private let defaults: UserDefaultsBox?

    public init(suiteName: String? = nil) {
        if let suiteName {
            defaults = UserDefaults(suiteName: suiteName).map(UserDefaultsBox.init)
        } else {
            defaults = UserDefaultsBox(.standard)
        }
    }

    public init(defaults: UserDefaults) {
        self.defaults = UserDefaultsBox(defaults)
    }

    public var hasUnreadablePreferences: Bool {
        !readID(Keys.light).isReadable || !readID(Keys.dark).isReadable || !appearanceModeIsReadable
    }

    public func loadSelection() -> (lightID: String, darkID: String)? {
        let light = readID(Keys.light)
        let dark = readID(Keys.dark)
        guard light.isReadable, dark.isReadable, light.value != nil || dark.value != nil else { return nil }
        return (light.value ?? BundledThemes.light.id, dark.value ?? BundledThemes.dark.id)
    }

    public func saveSelection(lightID: String, darkID: String) {
        // A temporary UI fallback is not authority to replace unreadable bytes.
        // Recheck both members at the write boundary, including a later writer.
        guard readID(Keys.light).isReadable, readID(Keys.dark).isReadable,
              Self.validID(lightID), Self.validID(darkID) else { return }
        defaults?.value.set(lightID, forKey: Keys.light)
        defaults?.value.set(darkID, forKey: Keys.dark)
    }

    public func loadAppearanceMode() -> ThemeAppearanceMode? {
        guard let rawValue = defaults?.value.object(forKey: Keys.appearanceMode) as? String else { return nil }
        return ThemeAppearanceMode(rawValue: rawValue)
    }

    public func saveAppearanceMode(_ mode: ThemeAppearanceMode) {
        guard appearanceModeIsReadable else { return }
        defaults?.value.set(mode.rawValue, forKey: Keys.appearanceMode)
    }

    private var appearanceModeIsReadable: Bool {
        guard let defaults else { return false }
        guard let object = defaults.value.object(forKey: Keys.appearanceMode) else { return true }
        guard let raw = object as? String else { return false }
        return ThemeAppearanceMode(rawValue: raw) != nil
    }

    private enum StoredID {
        case absent
        case value(String)
        case unreadable

        var isReadable: Bool {
            if case .unreadable = self {
                return false
            }
            return true
        }

        var value: String? {
            if case let .value(value) = self {
                return value
            }
            return nil
        }
    }

    private func readID(_ key: String) -> StoredID {
        guard let defaults else { return .unreadable }
        guard let object = defaults.value.object(forKey: key) else { return .absent }
        guard let value = object as? String, Self.validID(value) else { return .unreadable }
        return .value(value)
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private enum Keys {
        static let light = "MacDown2ThemeLight"
        static let dark = "MacDown2ThemeDark"
        static let appearanceMode = "MacDown2ThemeAppearanceMode"
    }
}

/// `UserDefaults` is safe for concurrent use but is not annotated Sendable by
/// Foundation. The preference-store protocol deliberately exposes only its
/// synchronous key-value operations.
private final class UserDefaultsBox: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}
