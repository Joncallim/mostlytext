import Foundation
import Testing
@testable import Themes

@MainActor
struct ThemeControllerCatalogTests {
    @Test func delayedCatalogRestoresPreferredCustomThemeWithoutPreferenceWrites() throws {
        let custom = try ThemeFile(theme: BundledThemes.dark)
        let preferences = FakeThemePreferenceStore()
        preferences.saveSelection(lightID: BundledThemes.light.id, darkID: custom.theme.id)
        let controller = ThemeController(preferenceStore: preferences, appearance: .dark)
        #expect(controller.current.id == BundledThemes.dark.id)
        #expect(try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 0, customThemes: [custom])))
        #expect(controller.current == custom.theme)
        #expect(preferences.saveCount == 1)
    }

    @Test func userChoiceDuringLoadWinsAndTheOtherPreferredSlotIsPreserved() throws {
        let light = try ThemeFile(theme: BundledThemes.light)
        let dark = try ThemeFile(theme: BundledThemes.dark)
        let preferences = FakeThemePreferenceStore()
        preferences.saveSelection(lightID: light.theme.id, darkID: dark.theme.id)
        let controller = ThemeController(preferenceStore: preferences)
        controller.selectLight(id: "paper")
        #expect(preferences.loadSelection()?.darkID == dark.theme.id)
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 1, customThemes: [light, dark]))
        #expect(controller.light.id == "paper")
        #expect(controller.dark == dark.theme)
        #expect(preferences.saveCount == 2)
    }

    @Test func staleCatalogCannotResurrectAnOlderThemeValue() throws {
        let first = try ThemeFile(theme: BundledThemes.light)
        var newer = first.theme
        newer.name = "Newer value"
        let second = try ThemeFile(theme: newer, stableID: first.stableID)
        let controller = ThemeController(preferenceStore: FakeThemePreferenceStore())
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 3, customThemes: [first]))
        controller.selectLight(id: first.theme.id)
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 4, customThemes: [second]))
        #expect(try !controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 3, customThemes: [first])))
        #expect(try !controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 4, customThemes: [])))
        #expect(controller.current == second.theme)
        controller.select(first.theme)
        #expect(controller.current == second.theme)
    }

    @Test func confirmedDeletionFallsBackOnceAndNeverDeletesAnotherUnknownPreference() throws {
        let custom = try ThemeFile(theme: BundledThemes.light)
        let unknownDark = UUID().uuidString.lowercased()
        let preferences = FakeThemePreferenceStore()
        preferences.saveSelection(lightID: custom.theme.id, darkID: unknownDark)
        let controller = ThemeController(preferenceStore: preferences)
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 1, customThemes: [custom]))
        #expect(controller.current == custom.theme)
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 2, customThemes: []))
        #expect(controller.current == BundledThemes.light)
        #expect(preferences.loadSelection()?.lightID == BundledThemes.light.id)
        #expect(preferences.loadSelection()?.darkID == unknownDark)
        #expect(preferences.saveCount == 2)
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 3, customThemes: []))
        #expect(preferences.saveCount == 2)
    }

    @Test func unknownStartupChoiceIsRetainedWithSafeMatchingFallbacks() throws {
        let preferences = FakeThemePreferenceStore()
        let lightID = UUID().uuidString.lowercased()
        let darkID = UUID().uuidString.lowercased()
        preferences.saveSelection(lightID: lightID, darkID: darkID)
        let controller = ThemeController(preferenceStore: preferences, appearance: .dark)
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 0, customThemes: []))
        #expect(controller.current.appearance == .dark)
        #expect(controller.light == BundledThemes.light)
        #expect(preferences.loadSelection()?.lightID == lightID)
        #expect(preferences.loadSelection()?.darkID == darkID)
        #expect(preferences.saveCount == 1)
    }

    @Test func appearanceChangeOfACustomThemeInvalidatesOnlyItsPreviousSlot() throws {
        let custom = try ThemeFile(theme: BundledThemes.light)
        let preferences = FakeThemePreferenceStore()
        let controller = ThemeController(preferenceStore: preferences)
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 1, customThemes: [custom]))
        controller.selectLight(id: custom.theme.id)
        var changed = custom.theme
        changed.appearance = .dark
        let moved = try ThemeFile(theme: changed, stableID: custom.stableID)
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 2, customThemes: [moved]))
        #expect(controller.light == BundledThemes.light)
        #expect(controller.dark == BundledThemes.dark)
        #expect(preferences.loadSelection()?.lightID == BundledThemes.light.id)
        #expect(preferences.loadSelection()?.darkID == BundledThemes.dark.id)
    }

    @Test func foreignOrRemovedMenuValueCannotBecomeTheCurrentTheme() throws {
        let preferences = FakeThemePreferenceStore()
        let controller = ThemeController(preferenceStore: preferences)
        let foreign = try ThemeFile(theme: BundledThemes.dark)
        controller.select(foreign.theme)
        #expect(preferences.saveCount == 0)
        #expect(controller.current == BundledThemes.light)
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 1, customThemes: [foreign]))
        try controller.applyCustomCatalog(ThemeCatalogSnapshot(revision: 2, customThemes: []))
        controller.select(foreign.theme)
        #expect(preferences.saveCount == 0)
    }

    @Test func resetPublishesBothChoicesOnceAndKeepsTheAppearanceMode() {
        let preferences = FakeThemePreferenceStore()
        let controller = ThemeController(preferenceStore: preferences)
        controller.selectLight(id: "paper")
        controller.selectDark(id: "midnight")
        controller.setAppearanceMode(.dark)
        let before = preferences.saveCount
        controller.resetThemeChoices()
        #expect(controller.light == BundledThemes.light)
        #expect(controller.dark == BundledThemes.dark)
        #expect(controller.current == BundledThemes.dark)
        #expect(controller.appearanceMode == .dark)
        #expect(preferences.saveCount == before + 1)
    }
}
