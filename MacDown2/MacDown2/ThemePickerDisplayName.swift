import Foundation
import Themes

/// Theme data keeps its authored name. Only these two descriptive built-in
/// choices need translated labels in the app's theme pickers and menu.
enum ThemePickerDisplayName {
    static func name(for theme: Theme, bundle: Bundle = .main) -> String {
        switch theme.id {
        case "high-contrast-light":
            String(localized: "High Contrast Light", bundle: bundle)
        case "high-contrast-dark":
            String(localized: "High Contrast Dark", bundle: bundle)
        default:
            theme.name
        }
    }

    static func menuName(for theme: Theme, selectedID: String, bundle: Bundle = .main) -> String {
        (selectedID == theme.id ? "✓ " : "    ") + name(for: theme, bundle: bundle)
    }
}
