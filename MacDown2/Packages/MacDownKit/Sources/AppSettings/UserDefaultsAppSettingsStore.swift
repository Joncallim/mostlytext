import CoreFoundation
import Foundation

/// `UserDefaults`-backed `AppSettingsStoring`. Each domain is one JSON blob
/// under one key, matching `WorkspaceStateStore.sidebarSectionExpanded`'s
/// existing whole-struct-as-one-key convention.
///
/// Accepts an injectable `UserDefaults` instance so callers can isolate
/// storage — production code passes the app's UI-testing-isolated suite the
/// same way `AppDelegate` already does for `FileTreePreferences` and
/// `WorkspaceStateStore`; tests pass a uniquely named suite.
@MainActor
public struct UserDefaultsAppSettingsStore: AppSettingsStoring {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var general: GeneralSettings {
        get { load(.general) }
        set { save(newValue, key: .general) }
    }

    public var editor: EditorSettings {
        get { load(.editor) }
        set { save(newValue, key: .editor) }
    }

    /// A read-only snapshot for import planning. A present value of the wrong
    /// property-list type is distinct from a genuinely absent editor domain.
    /// The importer must not turn `.unreadableNonData` into `.decode(nil)`.
    public enum EditorStoredDomain: Sendable, Equatable {
        case decoded(LegacyEditorDestinationEvidence)
        case unreadableNonData
    }

    public var editorStoredDomain: EditorStoredDomain {
        guard let object = defaults.object(forKey: Key.editor.rawValue) else {
            return .decoded(.decode(nil))
        }
        guard let data = object as? Data else { return .unreadableNonData }
        return .decoded(.decode(data))
    }

    public var markdown: MarkdownSettings {
        get { load(.markdown) }
        set { save(newValue, key: .markdown) }
    }

    public var previewExport: PreviewExportSettings {
        get { load(.previewExport) }
        set { save(newValue, key: .previewExport) }
    }

    public var formats: FormatSettings {
        get { load(.formats) }
        set { save(newValue, key: .formats) }
    }

    /// Absent data is the default. Present data is decoded through each domain's compatible `Decodable` (older
    /// schema-less blobs keep every valid value; see `EditorSettings.init(from:)`). Data that cannot be understood
    /// (malformed bytes, a wrong type, an out-of-range value, a newer `schemaVersion`) falls back to the default
    /// for the running session only: the raw bytes stay in `UserDefaults`, are reported by `unreadableDomains`, and
    /// are copied to the existing one-time preserved key when a later save is refused (#53).
    /// A backup never authorizes replacement of an unreadable primary value.
    private func load<T: AppSettingsDomain>(_ key: Key) -> T {
        if key == .editor {
            if case let .decoded(evidence) = editorStoredDomain,
               let settings = evidence.settings as? T {
                return settings
            }
            return T.defaultValue
        }
        guard let object = defaults.object(forKey: key.rawValue),
              let data = object as? Data,
              let value = Self.decode(T.self, from: data)
        else { return T.defaultValue }
        return value
    }

    private func save(_ value: some Encodable, key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        // Recheck at the write boundary: another store or a newer build may have replaced
        // the value since this session loaded it. Preserve every present value we cannot read.
        if let existing = defaults.object(forKey: key.rawValue) {
            guard let current = existing as? Data, key.decodes(current) else {
                preserveUnreadableBytes(for: key, ifDifferentFrom: data)
                return
            }
        }
        defaults.set(data, forKey: key.rawValue)
    }

    /// The highest settings schema this build understands. The historical schema has no version key (named
    /// "schema-less"); a blob that declares a larger `schemaVersion` is rejected on read and protected from
    /// ordinary writes. The first unreadable Data backup is retained for compatibility; the primary is also preserved.
    nonisolated static let supportedSchemaVersion = 1

    fileprivate nonisolated static func decode<T: AppSettingsDomain>(_: T.Type, from data: Data) -> T? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let object = object as? [String: Any]
        else { return nil }

        // A whole-domain save serializes only T's known fields. Treat an
        // unadmitted member as unreadable rather than accepting it and
        // silently dropping it on the next ordinary save. `schemaVersion` is
        // optional because the historical compatible blobs were schema-less.
        guard T.admitsStoredObject(object) else { return nil }

        if let declared = object["schemaVersion"] {
            guard isSupportedSchemaVersion(declared) else { return nil }
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private nonisolated static func isSupportedSchemaVersion(_ value: Any) -> Bool {
        // JSON booleans bridge to NSNumber, but are not schema versions. Check
        // the Core Foundation type identity before reading numeric accessors.
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return false }

        let numericValue = number.doubleValue
        guard numericValue.isFinite,
              numericValue.rounded(.towardZero) == numericValue
        else { return false }

        // NSNumber's fixed-width accessors do not trap for oversized values;
        // the explicit range and round-trip comparison reject values that
        // saturate or lose precision during accessor conversion, without
        // converting an untrusted value to Int. Lexical precision already
        // discarded by JSONSerialization cannot be recovered here.
        let version = number.int64Value
        return (1 ... Int64(supportedSchemaVersion)).contains(version)
            && Double(version) == numericValue
    }

    /// Domains whose stored values exist but cannot be read by this build. Ordinary writes to
    /// these domains are refused; other domains remain writable. Includes non-Data values.
    public var unreadableDomains: [String] {
        Key.allCases.compactMap { key in
            guard let value = defaults.object(forKey: key.rawValue) else { return nil }
            guard let data = value as? Data else { return key.rawValue }
            return key.decodes(data) ? nil : key.rawValue
        }
    }

    /// The first unreadable blob for `key`, kept verbatim (never overwritten once present).
    public func preservedUnreadableData(forDomain name: String) -> Data? {
        defaults.data(forKey: Self.preservedKey(for: name))
    }

    private static func preservedKey(for name: String) -> String {
        name + ".preservedUnreadable"
    }

    private func preserveUnreadableBytes(for key: Key, ifDifferentFrom replacement: Data) {
        guard let existing = defaults.data(forKey: key.rawValue), existing != replacement,
              !key.decodes(existing),
              defaults.data(forKey: Self.preservedKey(for: key.rawValue)) == nil
        else { return }
        defaults.set(existing, forKey: Self.preservedKey(for: key.rawValue))
    }

    private enum Key: String, CaseIterable {
        case general = "appSettings.general"
        case editor = "appSettings.editor"
        case markdown = "appSettings.markdown"
        case previewExport = "appSettings.previewExport"
        case formats = "appSettings.formats"

        func decodes(_ data: Data) -> Bool {
            switch self {
            case .general: UserDefaultsAppSettingsStore.decode(GeneralSettings.self, from: data) != nil
            case .editor: LegacyEditorDestinationEvidence.decode(data).settings != nil
            case .markdown: UserDefaultsAppSettingsStore.decode(MarkdownSettings.self, from: data) != nil
            case .previewExport: UserDefaultsAppSettingsStore.decode(PreviewExportSettings.self, from: data) != nil
            case .formats: UserDefaultsAppSettingsStore.decode(FormatSettings.self, from: data) != nil
            }
        }
    }
}
