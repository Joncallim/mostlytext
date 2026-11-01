import Foundation

/// Loads the shipped themes from `Bundle.module`.
public enum BundledThemes {
    public static let light: Theme = load("Tomorrow Light", appearance: .light)
    public static let dark: Theme = load("Tomorrow Dark", appearance: .dark)
    public static let all: [Theme] = [
        light, dark,
        load("Paper", appearance: .light),
        load("Daybreak", appearance: .light),
        load("High Contrast Light", appearance: .light),
        load("Slate", appearance: .dark),
        load("Midnight", appearance: .dark),
        load("High Contrast Dark", appearance: .dark),
    ]

    static func load(_ resource: String, appearance: ThemeAppearance) -> Theme {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let theme = try? JSONDecoder().decode(Theme.self, from: data)
        else {
            assertionFailure("Bundled theme \(resource).json is missing or corrupt; falling back to a minimal theme.")
            return minimalTheme(
                id: resource.lowercased().replacingOccurrences(of: " ", with: "-"),
                appearance: appearance
            )
        }
        return theme
    }

    static func minimalTheme(id: String, appearance: ThemeAppearance) -> Theme {
        let black = ThemeColor(red: 0, green: 0, blue: 0)
        let white = ThemeColor(red: 1, green: 1, blue: 1)
        return Theme(
            id: id,
            name: id,
            appearance: appearance,
            chrome: EditorChrome(
                background: appearance == .dark ? black : white,
                foreground: appearance == .dark ? white : black,
                caret: appearance == .dark ? white : black,
                selection: appearance == .dark
                    ? ThemeColor(red: 0.3, green: 0.3, blue: 0.3)
                    : ThemeColor(red: 0.7, green: 0.8, blue: 1)
            ),
            tokenStyles: [:]
        )
    }
}
