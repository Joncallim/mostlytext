import Foundation
import Observation

/// Single source of truth for the active theme. App-wide (one instance).
@MainActor
@Observable
public final class ThemeController {
    public private(set) var light: Theme
    public private(set) var dark: Theme
    public private(set) var systemAppearance: ThemeAppearance
    public private(set) var appearanceMode: ThemeAppearanceMode
    public private(set) var appearance: ThemeAppearance
    public private(set) var current: Theme
    public private(set) var hasUnreadablePreferences: Bool

    /// AppKit owns the actual application appearance. The app assigns this
    /// callback after construction so Themes stays platform-neutral.
    public var appearanceModeDidChange: ((ThemeAppearanceMode) -> Void)?

    private var availableThemes: [Theme]
    private var preferredLightID: String
    private var preferredDarkID: String
    private var latestCatalogRevision: UInt64?
    private let preferenceStore: ThemePreferenceStoring

    public init(
        available: [Theme] = BundledThemes.all,
        preferenceStore: ThemePreferenceStoring = UserDefaultsThemePreferenceStore(),
        appearance: ThemeAppearance = .light
    ) {
        availableThemes = available
        self.preferenceStore = preferenceStore
        hasUnreadablePreferences = preferenceStore.hasUnreadablePreferences
        let initialAppearanceMode = preferenceStore.loadAppearanceMode() ?? .system
        systemAppearance = appearance
        appearanceMode = initialAppearanceMode
        let effectiveAppearance = initialAppearanceMode.resolvedAppearance(systemAppearance: appearance)
        self.appearance = effectiveAppearance

        let defaultLight = available.first { $0.appearance == .light } ?? BundledThemes.light
        let defaultDark = available.first { $0.appearance == .dark } ?? BundledThemes.dark

        let selection = preferenceStore.loadSelection()
        preferredLightID = selection?.lightID ?? defaultLight.id
        preferredDarkID = selection?.darkID ?? defaultDark.id
        let initialLight: Theme
        let initialDark: Theme
        if let selection {
            initialLight = available.first { $0.id == selection.lightID && $0.appearance == .light } ?? defaultLight
            initialDark = available.first { $0.id == selection.darkID && $0.appearance == .dark } ?? defaultDark
        } else {
            initialLight = defaultLight
            initialDark = defaultDark
        }

        light = initialLight
        dark = initialDark
        current = effectiveAppearance == .dark ? initialDark : initialLight
    }

    public var available: [Theme] {
        availableThemes
    }

    /// Fed by the app from macOS appearance changes.
    public func setAppearance(_ appearance: ThemeAppearance) {
        systemAppearance = appearance
        guard appearanceMode == .system else { return }
        apply(appearance)
    }

    /// Applies the app-wide choice without changing either saved theme slot.
    public func setAppearanceMode(_ mode: ThemeAppearanceMode) {
        guard appearanceMode != mode else { return }
        appearanceMode = mode
        preferenceStore.saveAppearanceMode(mode)
        refreshPreferenceStatus()
        apply(mode.resolvedAppearance(systemAppearance: systemAppearance))
        appearanceModeDidChange?(mode)
    }

    /// Select a theme for its appearance slot.
    ///
    /// If the theme matches the current system appearance, it becomes
    /// `current` immediately. Otherwise the slot is saved so that future
    /// `setAppearance` calls use the user's choice for that appearance.
    public func select(_ theme: Theme) {
        guard availableThemes.contains(where: { $0.id == theme.id && $0.appearance == theme.appearance })
        else { return }
        if theme.appearance == .light {
            selectLight(id: theme.id)
        } else {
            selectDark(id: theme.id)
        }
    }

    public func selectLight(id: String) {
        guard let theme = availableThemes.first(where: { $0.id == id && $0.appearance == .light }) else { return }
        light = theme
        preferredLightID = theme.id
        if appearance == .light {
            current = theme
        }
        persistSelection()
    }

    public func selectDark(id: String) {
        guard let theme = availableThemes.first(where: { $0.id == id && $0.appearance == .dark }) else { return }
        dark = theme
        preferredDarkID = theme.id
        if appearance == .dark {
            current = theme
        }
        persistSelection()
    }

    /// Accept revisions from the single app-wide catalog owner. Pending invalid
    /// writes retain their known-good values in that owner's snapshot.
    @discardableResult
    public func applyCustomCatalog(_ snapshot: ThemeCatalogSnapshot) -> Bool {
        refreshPreferenceStatus()
        if let latestCatalogRevision, snapshot.revision <= latestCatalogRevision {
            return false
        }
        let knownLight = availableThemes.contains { $0.id == preferredLightID && $0.appearance == .light }
        let knownDark = availableThemes.contains { $0.id == preferredDarkID && $0.appearance == .dark }
        availableThemes = snapshot.available
        latestCatalogRevision = snapshot.revision
        let nextLight = availableThemes.first { $0.id == preferredLightID && $0.appearance == .light }
        let nextDark = availableThemes.first { $0.id == preferredDarkID && $0.appearance == .dark }
        light = nextLight ?? BundledThemes.light
        dark = nextDark ?? BundledThemes.dark
        let lostLight = knownLight && nextLight == nil
        let lostDark = knownDark && nextDark == nil
        if lostLight {
            preferredLightID = light.id
        }
        if lostDark {
            preferredDarkID = dark.id
        }
        current = appearance == .dark ? dark : light
        if lostLight || lostDark {
            persistSelection()
        }
        return true
    }

    public func resetThemeChoices() {
        light = availableThemes.first { $0.id == BundledThemes.light.id } ?? BundledThemes.light
        dark = availableThemes.first { $0.id == BundledThemes.dark.id } ?? BundledThemes.dark
        preferredLightID = light.id
        preferredDarkID = dark.id
        current = appearance == .dark ? dark : light
        persistSelection()
    }

    public func refreshPreferenceStatus() {
        hasUnreadablePreferences = preferenceStore.hasUnreadablePreferences
    }

    private func persistSelection() {
        preferenceStore.saveSelection(lightID: preferredLightID, darkID: preferredDarkID)
        refreshPreferenceStatus()
    }

    private func apply(_ appearance: ThemeAppearance) {
        self.appearance = appearance
        current = appearance == .dark ? dark : light
    }
}
