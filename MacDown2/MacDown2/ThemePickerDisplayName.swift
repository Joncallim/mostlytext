import FileCore
import Foundation
import Themes

/// Theme data keeps its authored name. Only these two descriptive built-in
/// choices need translated labels in the app's theme pickers and menu.
enum ThemePickerDisplayName {
    static func name(for theme: Theme, bundle: Bundle = .main, locale: Locale = .current) -> String {
        guard theme.id == "high-contrast-light" || theme.id == "high-contrast-dark" else {
            return theme.name
        }
        let bundle = ViewLocalizationBundle.resolve(locale: locale, in: bundle)
        return switch theme.id {
        case "high-contrast-light":
            String(localized: "High Contrast Light", bundle: bundle, locale: locale)
        case "high-contrast-dark":
            String(localized: "High Contrast Dark", bundle: bundle, locale: locale)
        default: theme.name
        }
    }

    static func menuName(
        for theme: Theme, selectedID: String, bundle: Bundle = .main, locale: Locale = .current
    ) -> String {
        (selectedID == theme.id ? "✓ " : "    ") + name(for: theme, bundle: bundle, locale: locale)
    }
}
