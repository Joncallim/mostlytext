@testable import AppSettings
import Foundation
import Testing

struct StoredSettingsJSONTests {
    @Test(arguments: ["1", "1.0", "1e0", "1E+0", "10e-1", "0.01e2", "100.00e-2"])
    func equivalentSupportedIntegerSpellings(_ spelling: String) throws {
        let fields = try #require(StoredSettingsJSON.fields(in: Data("{\"schemaVersion\":\(spelling)}".utf8)))
        #expect(StoredSettingsJSON.version(in: fields) == .current)
    }

    @Test(arguments: ["2", "1.5e1", "99999999999999999999999", "1e99999999999999999999999"])
    func largerExactIntegersAreFutureVersions(_ spelling: String) throws {
        let fields = try #require(StoredSettingsJSON.fields(in: Data("{\"schemaVersion\":\(spelling)}".utf8)))
        #expect(StoredSettingsJSON.version(in: fields) == .future)
    }

    @Test(arguments: [
        "true", "null", "\"1\"", "0", "-0", "-1", "1.01", "0.99999999999999999999",
        "1.00000000000000000001", "1e-99999999999999999999999",
    ])
    func malformedVersionsNeverBecomeCurrent(_ spelling: String) throws {
        let fields = try #require(StoredSettingsJSON.fields(in: Data("{\"schemaVersion\":\(spelling)}".utf8)))
        #expect(StoredSettingsJSON.version(in: fields) == .malformed)
    }

    @Test func strictObjectAdmissionPreservesTheRootKeyDistinctions() {
        for text in ["[]", "{\"a\":1,\"\\u0061\":2}", "{\"é\":1,\"e\\u0301\":2}"] {
            #expect(StoredSettingsJSON.fields(in: Data(text.utf8)) == nil)
        }
        #expect(StoredSettingsJSON.fields(in: Data([0xFF])) == nil)
        #expect(StoredSettingsJSON.fields(in: Data(repeating: 32, count: 1_048_577)) == nil)
    }
}

enum StoredSettingsDomainFixture: String, CaseIterable {
    case general, editor, markdown, previewExport, formats

    var key: String {
        "appSettings." + rawValue
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        return switch self {
        case .general: try encoder.encode(GeneralSettings.default)
        case .editor: try encoder.encode(EditorSettings.default)
        case .markdown: try encoder.encode(MarkdownSettings.default)
        case .previewExport: try encoder.encode(PreviewExportSettings.default)
        case .formats: try encoder.encode(FormatSettings.default)
        }
    }

    @MainActor func saveDefault(to store: inout UserDefaultsAppSettingsStore) {
        switch self {
        case .general: store.general = .default
        case .editor: store.editor = .default
        case .markdown: store.markdown = .default
        case .previewExport: store.previewExport = .default
        case .formats: store.formats = .default
        }
    }
}

@MainActor
struct StoredSettingsProtectionTests {
    @Test(arguments: StoredSettingsDomainFixture.allCases,
          ["1.0000000000000000001", "0.99999999999999999999", "2", "true", "null"])
    func unsupportedVersionBytesSurviveOrdinarySave(_ domain: StoredSettingsDomainFixture,
                                                    _ version: String) throws {
        try isolated { defaults, store in
            let valid = try #require(String(data: domain.encoded(), encoding: .utf8))
            let raw = Data((String(valid.dropLast()) + ",\"schemaVersion\":" + version + "}").utf8)
            defaults.set(raw, forKey: domain.key)
            #expect(store.unreadableDomains == [domain.key])
            domain.saveDefault(to: &store)
            #expect(defaults.data(forKey: domain.key) == raw)
        }
    }

    @Test(arguments: StoredSettingsDomainFixture.allCases)
    func duplicateVersionMembersCannotBeDiscardedByOrdinarySave(_ domain: StoredSettingsDomainFixture) throws {
        try isolated { defaults, store in
            let valid = try #require(String(data: domain.encoded(), encoding: .utf8))
            let raw = Data((String(valid.dropLast()) + ",\"schemaVersion\":2,\"schemaVersion\":1}").utf8)
            defaults.set(raw, forKey: domain.key)
            #expect(store.unreadableDomains == [domain.key])
            domain.saveDefault(to: &store)
            #expect(defaults.data(forKey: domain.key) == raw)
        }
    }

    @Test(arguments: StoredSettingsDomainFixture.allCases, ["1", "1.0", "10e-1"])
    func supportedEquivalentVersionsRemainReadable(_ domain: StoredSettingsDomainFixture,
                                                   _ version: String) throws {
        try isolated { defaults, store in
            let valid = try #require(String(data: domain.encoded(), encoding: .utf8))
            let raw = Data((String(valid.dropLast()) + ",\"schemaVersion\":" + version + "}").utf8)
            defaults.set(raw, forKey: domain.key)
            #expect(store.unreadableDomains.isEmpty)
            domain.saveDefault(to: &store)
            #expect(store.unreadableDomains.isEmpty)
        }
    }

    private func isolated(_ body: (UserDefaults, inout UserDefaultsAppSettingsStore) throws -> Void) throws {
        let suite = "strict-settings-json-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var store = UserDefaultsAppSettingsStore(defaults: defaults)
        try body(defaults, &store)
    }
}
