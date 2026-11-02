@testable import AppSettings
import Foundation
import Testing

@MainActor
@Suite("Shared editor destination admission")
struct EditorStoredDomainIntegrationTests {
    private static let key = "appSettings.editor"

    private func isolated(_ body: (UserDefaults, UserDefaultsAppSettingsStore) throws -> Void) rethrows {
        let suite = "editor-admission-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("could not create isolated settings suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, UserDefaultsAppSettingsStore(defaults: defaults))
    }

    @Test func absentDomainStaysDistinctAndDoesNotCreateDefaults() {
        isolated { defaults, store in
            guard case let .decoded(evidence) = store.editorStoredDomain else {
                Issue.record("absent editor domain must be recorded")
                return
            }
            #expect(evidence.status == .absent)
            #expect(evidence.settings == nil)
            #expect(store.editor == .default)
            #expect(defaults.object(forKey: Self.key) == nil)
        }
    }

    @Test func startupAndImportPlanningSeeTheSameAdmittedEditorBytes() throws {
        try isolated { defaults, store in
            let raw = try JSONEncoder().encode(EditorSettings(showsStatusBar: false, smartHome: false))
            defaults.set(raw, forKey: Self.key)
            guard case let .decoded(evidence) = store.editorStoredDomain else {
                Issue.record("present editor Data must be decoded")
                return
            }
            #expect(evidence.status == .valid)
            #expect(evidence.settings == store.editor)
            #expect(evidence.settings?.showsStatusBar == false)
            #expect(evidence.persisted[.smartHome] == false)
            let source = try LegacyPreferenceSnapshot(domain: ["editorSmartHome": true])
            let plan = LegacyImportPlan(source: source, destination: evidence)
            #expect(plan.defaultFills.isEmpty)
            #expect(plan.entries.first?.disposition == .retainPersisted(false, suggested: true))
            #expect(defaults.data(forKey: Self.key) == raw)
        }
    }

    @Test func presentNonDataEditorValueIsUnreadableRatherThanAbsent() {
        isolated { defaults, store in
            let original = "not editor JSON"
            defaults.set(original, forKey: Self.key)
            #expect(store.editorStoredDomain == .unreadableNonData)
            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.key])
            var writableStore = store
            writableStore.editor = EditorSettings(indentationWidth: 3)
            #expect(defaults.object(forKey: Self.key) as? String == original)
            #expect(store.editorStoredDomain == .unreadableNonData)
        }
    }

    @Test func duplicateEditorKeysAreProtectedFromOrdinaryStartupAndSave() throws {
        try isolated { defaults, store in
            var writableStore = store
            let valid = try JSONEncoder().encode(EditorSettings())
            let text = try #require(String(data: valid, encoding: .utf8))
            let raw = Data((String(text.dropLast()) + ",\"smartHome\":true}").utf8)
            defaults.set(raw, forKey: Self.key)
            guard case let .decoded(evidence) = store.editorStoredDomain else {
                Issue.record("present editor Data must be decoded")
                return
            }
            #expect(evidence.status == .malformed)
            #expect(evidence.settings == nil)
            #expect(store.editor == .default)
            #expect(store.unreadableDomains == [Self.key])
            writableStore.editor = EditorSettings(indentationWidth: 3)
            #expect(defaults.data(forKey: Self.key) == raw)
            #expect(store.preservedUnreadableData(forDomain: Self.key) == raw)
        }
    }
}
