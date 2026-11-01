import Foundation
import Testing
@testable import Themes

@MainActor
struct ThemePreferenceCompatibilityTests {
    private struct Suite {
        let name: String
        let defaults: UserDefaults

        init() throws {
            name = "MostlyText-ThemeCompatibility-" + UUID().uuidString
            defaults = try #require(UserDefaults(suiteName: name))
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: name)
        }
    }

    @Test func aPartialPairPreservesThePresentSlotWithoutSeedingDefaults() throws {
        for key in ["MacDown2ThemeLight", "MacDown2ThemeDark"] {
            let suite = try Suite(); defer { suite.cleanup() }
            let id = UUID().uuidString.lowercased()
            suite.defaults.set(id, forKey: key)
            let before = suite.defaults.persistentDomain(forName: suite.name) as NSDictionary?
            let store = UserDefaultsThemePreferenceStore(defaults: suite.defaults)
            let selection = try #require(store.loadSelection())
            #expect(selection.lightID == (key == "MacDown2ThemeLight" ? id : BundledThemes.light.id))
            #expect(selection.darkID == (key == "MacDown2ThemeDark" ? id : BundledThemes.dark.id))
            #expect((suite.defaults.persistentDomain(forName: suite.name) as NSDictionary?) == before)
        }
    }

    @Test func choosingOneSlotDoesNotEraseTheOtherStillUnloadedChoice() throws {
        let suite = try Suite(); defer { suite.cleanup() }
        let id = UUID().uuidString.lowercased()
        suite.defaults.set(id, forKey: "MacDown2ThemeLight")
        let controller = ThemeController(preferenceStore: UserDefaultsThemePreferenceStore(defaults: suite.defaults))
        controller.selectDark(id: "midnight")
        #expect(suite.defaults.object(forKey: "MacDown2ThemeLight") as? String == id)
        #expect(suite.defaults.object(forKey: "MacDown2ThemeDark") as? String == "midnight")
    }

    @Test(arguments: ["data", "number", "boolean", "array", "dictionary", "empty", "control"])
    func unreadableSelectionValuesAreNotCoercedOrOverwritten(kind: String) throws {
        let suite = try Suite(); defer { suite.cleanup() }
        let value: Any = switch kind {
        case "data": Data([0xAA, 0xBB])
        case "number": 17
        case "boolean": true
        case "array": ["future"]
        case "dictionary": ["schemaVersion": 99]
        case "empty": ""
        default: "bad\u{0000}id"
        }
        suite.defaults.set(value, forKey: "MacDown2ThemeLight")
        suite.defaults.set("midnight", forKey: "MacDown2ThemeDark")
        let before = suite.defaults.persistentDomain(forName: suite.name) as NSDictionary?
        let store = UserDefaultsThemePreferenceStore(defaults: suite.defaults)
        #expect(store.loadSelection() == nil)
        #expect(store.hasUnreadablePreferences)
        store.saveSelection(lightID: "paper", darkID: "slate")
        #expect((suite.defaults.persistentDomain(forName: suite.name) as NSDictionary?) == before)
    }

    @Test func aLaterUnreadableGenerationIsPreservedAtTheWriteBoundary() throws {
        let suite = try Suite(); defer { suite.cleanup() }
        suite.defaults.set("paper", forKey: "MacDown2ThemeLight")
        suite.defaults.set("midnight", forKey: "MacDown2ThemeDark")
        let store = UserDefaultsThemePreferenceStore(defaults: suite.defaults)
        _ = store.loadSelection()
        let future = Data("future version bytes".utf8)
        suite.defaults.set(future, forKey: "MacDown2ThemeLight")
        store.saveSelection(lightID: "daybreak", darkID: "slate")
        #expect(suite.defaults.data(forKey: "MacDown2ThemeLight") == future)
        #expect(suite.defaults.object(forKey: "MacDown2ThemeDark") as? String == "midnight")
    }

    @Test func anUnknownAppearanceModeIsRetainedWhileSelectionRemainsWritable() throws {
        let suite = try Suite(); defer { suite.cleanup() }
        suite.defaults.set("future-mode", forKey: "MacDown2ThemeAppearanceMode")
        let store = UserDefaultsThemePreferenceStore(defaults: suite.defaults)
        #expect(store.loadAppearanceMode() == nil)
        #expect(store.hasUnreadablePreferences)
        store.saveAppearanceMode(.dark)
        #expect(suite.defaults.object(forKey: "MacDown2ThemeAppearanceMode") as? String == "future-mode")
        store.saveSelection(lightID: "paper", darkID: "midnight")
        #expect(store.loadSelection()?.lightID == "paper")
    }

    @Test func knownFutureThemeIDsAreRetainedWithTemporaryDisplayedFallbacks() throws {
        let suite = try Suite(); defer { suite.cleanup() }
        let light = UUID().uuidString.lowercased(); let dark = UUID().uuidString.lowercased()
        suite.defaults.set(light, forKey: "MacDown2ThemeLight")
        suite.defaults.set(dark, forKey: "MacDown2ThemeDark")
        let controller = ThemeController(preferenceStore: UserDefaultsThemePreferenceStore(defaults: suite.defaults))
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 0, customThemes: []))
        #expect(controller.current == BundledThemes.light)
        #expect(suite.defaults.object(forKey: "MacDown2ThemeLight") as? String == light)
        #expect(suite.defaults.object(forKey: "MacDown2ThemeDark") as? String == dark)
    }
}
