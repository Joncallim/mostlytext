@testable import AppSettings
import Foundation
import Testing

@Suite("Conditional saved editor publication")
@MainActor
struct LegacyEditorPublicationTests {
    private let key = "appSettings.editor"

    private func isolated(
        _ body: (String, UserDefaults, inout UserDefaultsAppSettingsStore) throws -> Void
    ) throws {
        let name = "com.mostlytext.tests.publication.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var store = try UserDefaultsAppSettingsStore(persistentDomainName: name)
        try body(name, defaults, &store)
    }

    private func source(_ value: Bool = false) throws -> LegacyPreferenceSnapshot {
        try LegacyPreferenceSnapshot(domain: ["editorSmartHome": value, "editorConvertTabs": false])
    }

    private func proposal(
        _ store: UserDefaultsAppSettingsStore,
        replacing: Set<LegacyImportPlan.Destination> = []
    ) throws -> LegacyEditorWriteProposal {
        let source = try source()
        let saved = try store.legacyEditorDestination()
        guard case let .decoded(destination) = saved else { throw TestFailure.invalidFixture }
        return try LegacyEditorWriteProposal(
            plan: LegacyImportPlan(source: source, destination: destination),
            source: source, storedDestination: saved, selected: [.smartHome], replacing: replacing
        )
    }

    @Test func absentDomainPublishesAndReadsBackExactBytes() throws {
        try isolated { name, defaults, store in
            let proposed = try proposal(store)
            #expect(proposed.beforeRevision == "absent")
            #expect(try store.publishLegacyEditorChanges(proposed, currentSource: source()) == .applied)
            #expect(defaults.persistentDomain(forName: name)?[key] as? Data == proposed.desiredData)
            #expect(!store.editor.smartHome)
            #expect(store.editor.convertsTabsToSpaces)
            let reopened = try UserDefaultsAppSettingsStore(persistentDomainName: name)
            #expect(reopened.editor == store.editor)
        }
    }

    @Test func registeredFallbackDoesNotEstablishSavedPresence() throws {
        try isolated { name, defaults, store in
            // Registration is a process-wide volatile fallback; restore it
            // before another fixture can observe this synthetic value.
            let registration = store.defaults.volatileDomain(forName: UserDefaults.registrationDomain)
            defer { store.defaults.setVolatileDomain(registration, forName: UserDefaults.registrationDomain) }
            store.defaults.register(defaults: [key: Data([255])])
            #expect(store.defaults.object(forKey: key) as? Data == Data([255]))
            #expect(defaults.persistentDomain(forName: name)?[key] == nil)
            #expect(store.editor == .default)
            #expect(store.unreadableDomains.isEmpty)
            let proposed = try proposal(store)
            #expect(proposed.beforeRevision == "absent")
            #expect(try store.publishLegacyEditorChanges(proposed, currentSource: source()) == .applied)
        }
    }

    @Test func ordinaryBoundSaveAlsoIgnoresUnreadableFallback() throws {
        try isolated { name, defaults, store in
            let registration = store.defaults.volatileDomain(forName: UserDefaults.registrationDomain)
            defer { store.defaults.setVolatileDomain(registration, forName: UserDefaults.registrationDomain) }
            store.defaults.register(defaults: [key: Data([255])])
            let expected = EditorSettings(indentationWidth: 7, smartHome: false)
            store.editor = expected
            #expect(store.editor == expected)
            #expect(defaults.persistentDomain(forName: name)?[key] is Data)
        }
    }

    @Test func replacementNeedsConsentAndPreservesEveryUnselectedField() throws {
        try isolated { _, _, store in
            var expected = EditorSettings(font: .init(familyName: "Saved Family", size: 19),
                                          wrapsLines: false, showsInvisibles: true, indentationWidth: 7,
                                          convertsTabsToSpaces: true)
            store.editor = expected
            #expect(throws: LegacyEditorWriteProposal.Failure.replacementConsentRequired) {
                try proposal(store)
            }
            let proposed = try proposal(store, replacing: [.smartHome])
            #expect(try store.publishLegacyEditorChanges(proposed, currentSource: source()) == .applied)
            expected.smartHome = false
            #expect(store.editor == expected)
        }
    }

    @Test func ordinaryEditAfterPlanningIsPreservedAsConflict() throws {
        try isolated { name, defaults, store in
            let proposed = try proposal(store)
            var another = try UserDefaultsAppSettingsStore(persistentDomainName: name)
            another.editor = EditorSettings(indentationWidth: 6)
            let before = defaults.persistentDomain(forName: name)?[key] as? Data
            #expect(try store.publishLegacyEditorChanges(proposed, currentSource: source()) == .conflict)
            #expect(defaults.persistentDomain(forName: name)?[key] as? Data == before)
            #expect(store.editor.indentationWidth == 6)
        }
    }

    @Test func unreadableFutureAndNonDataReplacementsRemainUntouched() throws {
        try isolated { name, defaults, store in
            let proposed = try proposal(store)
            for raw in [
                Data([255]), Data("{\"schemaVersion\":2}".utf8),
                Data("{\"schemaVersion\":1,\"schemaVersion\":1}".utf8),
            ] {
                defaults.set(raw, forKey: key)
                #expect(try store.publishLegacyEditorChanges(proposed, currentSource: source()) == .conflict)
                #expect(defaults.persistentDomain(forName: name)?[key] as? Data == raw)
            }
            defaults.set("protected non-data", forKey: key)
            #expect(try store.publishLegacyEditorChanges(proposed, currentSource: source()) == .conflict)
            #expect(defaults.persistentDomain(forName: name)?[key] as? String == "protected non-data")
            #expect(defaults.persistentDomain(forName: name)?.count == 1)
        }
    }

    @Test func changedSourceCannotAuthorizeTheFirstWrite() throws {
        try isolated { name, defaults, store in
            let proposed = try proposal(store)
            #expect(throws: UserDefaultsAppSettingsStore.LegacyPublicationFailure.sourceChanged) {
                try store.publishLegacyEditorChanges(proposed, currentSource: source(true))
            }
            #expect(defaults.persistentDomain(forName: name)?[key] == nil)
        }
    }

    @Test func repeatedPublicationAcknowledgesDesiredAndPreservesLaterEdit() throws {
        try isolated { name, defaults, store in
            let proposed = try proposal(store)
            #expect(try store.publishLegacyEditorChanges(proposed, currentSource: source()) == .applied)
            // A source change after the completed write does not replay import.
            #expect(try store.publishLegacyEditorChanges(proposed, currentSource: source(true)) == .alreadyApplied)
            store.editor = EditorSettings(indentationWidth: 8)
            let later = defaults.persistentDomain(forName: name)?[key] as? Data
            #expect(try store.publishLegacyEditorChanges(proposed, currentSource: source()) == .conflict)
            #expect(defaults.persistentDomain(forName: name)?[key] as? Data == later)
        }
    }

    @Test func genericInjectedStoreCannotPublishOrInventDomainIdentity() throws {
        try isolated { _, defaults, store in
            let proposed = try proposal(store)
            let unbound = UserDefaultsAppSettingsStore(defaults: defaults)
            #expect(throws: UserDefaultsAppSettingsStore.LegacyPublicationFailure.unboundPersistenceDomain) {
                try unbound.legacyEditorDestination()
            }
            #expect(throws: UserDefaultsAppSettingsStore.LegacyPublicationFailure.unboundPersistenceDomain) {
                try unbound.publishLegacyEditorChanges(proposed, currentSource: source())
            }
        }
    }

    @Test func invalidSourceAndSystemDomainNamesAreRefusedBeforeAccess() {
        for name in [
            "", " ", "NSGlobalDomain", "NSArgumentDomain", "NSRegistrationDomain", ".invalid",
            "com..invalid", "com.bad/name", "com.bad\0name", "com.éxample.app", "com.-invalid",
            "com.invalid-", "com.apple", "com.apple.synthetic", "com.uranusjr.macdown",
            "COM.URANUSJR.MACDOWN", "com.uranusjr.macdown.synthetic", "com.uranusjr.macdown2",
            "com." + String(repeating: "a", count: 64),
        ] {
            #expect(throws: UserDefaultsAppSettingsStore.LegacyPublicationFailure.invalidPersistenceDomain) {
                try UserDefaultsAppSettingsStore(persistentDomainName: name)
            }
        }
    }

    @Test func failedReadbackDoesNotAcknowledgeCompletion() throws {
        try isolated { name, defaults, store in
            let proposed = try proposal(store)
            let refusing = try #require(RefusingDefaults(suiteName: name))
            let writer = UserDefaultsAppSettingsStore(defaults: refusing, persistenceDomainName: name)
            #expect(throws: UserDefaultsAppSettingsStore.LegacyPublicationFailure.readbackFailed) {
                try writer.publishLegacyEditorChanges(proposed, currentSource: source())
            }
            #expect(defaults.persistentDomain(forName: name)?[key] == nil)
        }
    }

    @Test func changedReadbackIsPreservedWithoutRollback() throws {
        try isolated { name, defaults, store in
            let proposed = try proposal(store)
            let replacing = try #require(ReplacingDefaults(suiteName: name))
            let writer = UserDefaultsAppSettingsStore(defaults: replacing, persistenceDomainName: name)
            #expect(throws: UserDefaultsAppSettingsStore.LegacyPublicationFailure.readbackFailed) {
                try writer.publishLegacyEditorChanges(proposed, currentSource: source())
            }
            #expect(defaults.persistentDomain(forName: name)?[key] as? String == "later value")
        }
    }

    @Test func boundOrdinarySavePreservesUnreadablePrimaryAndItsOwnBackup() throws {
        try isolated { name, defaults, store in
            let registration = store.defaults.volatileDomain(forName: UserDefaults.registrationDomain)
            defer { store.defaults.setVolatileDomain(registration, forName: UserDefaults.registrationDomain) }
            let backupKey = key + ".preservedUnreadable"
            store.defaults.register(defaults: [backupKey: Data([1])])
            #expect(store.preservedUnreadableData(forDomain: key) == nil)
            let raw = Data("{\"schemaVersion\":2}".utf8)
            defaults.set(raw, forKey: key)
            store.editor = .default
            #expect(store.unreadableDomains == [key])
            #expect(defaults.persistentDomain(forName: name)?[key] as? Data == raw)
            #expect(store.preservedUnreadableData(forDomain: key) == raw)
            #expect(defaults.persistentDomain(forName: name)?[backupKey] as? Data == raw)
        }
    }

    private enum TestFailure: Error { case invalidFixture }
}

private final class RefusingDefaults: UserDefaults, @unchecked Sendable {
    override func set(_: Any?, forKey _: String) {}
}

private final class ReplacingDefaults: UserDefaults, @unchecked Sendable {
    override func set(_: Any?, forKey key: String) {
        super.set("later value", forKey: key)
    }
}
