import AppKit

extension AppDelegate {
    @objc func systemAppearanceChanged() {
        guard themeController.appearanceMode == .system else { return }
        syncThemeAppearance()
    }

    func connectThemeAppearanceOverride() {
        themeController.appearanceModeDidChange = { [weak self] _ in
            self?.applyThemeAppearanceOverride()
        }
    }

    func applyThemeAppearanceOverride() {
        switch themeController.appearanceMode {
        case .system:
            NSApp.appearance = nil
            syncThemeAppearance()
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func syncThemeAppearance() {
        themeController.setAppearance(NSApp.effectiveAppearance.themeAppearance)
    }
}
