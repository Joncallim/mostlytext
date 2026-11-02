import Foundation

/// One immutable semantic palette for editor, preview and static presentation.
/// Resolving colors does not parse or mutate document content.
public struct ResolvedPresentationPalette: Sendable, Equatable {
    public let background: ThemeColor
    public let foreground: ThemeColor
    public let caret: ThemeColor
    public let selectionBackground: ThemeColor
    public let selectionForeground: ThemeColor
    public let currentLine: ThemeColor
    public let gutterForeground: ThemeColor
    public let gutterBackground: ThemeColor
    public let statusForeground: ThemeColor
    public let statusBackground: ThemeColor
    public let invisibles: ThemeColor
    public let secondaryCaret: ThemeColor
    public let heading: ThemeColor
    public let link: ThemeColor
    public let muted: ThemeColor
    public let rule: ThemeColor
    public let codeForeground: ThemeColor
    public let codeBackground: ThemeColor
    public let quoteForeground: ThemeColor
    public let quoteBackground: ThemeColor
    public let quoteBorder: ThemeColor

    public init(theme: Theme) {
        let chrome = theme.chrome
        background = chrome.background
        foreground = chrome.foreground
        caret = chrome.caret
        selectionBackground = chrome.selection
        selectionForeground = chrome.foreground
        currentLine = chrome.currentLine ?? chrome.foreground.withAlpha(0.05)
        gutterForeground = chrome.foreground
        gutterBackground = chrome.background
        statusForeground = chrome.foreground
        statusBackground = chrome.background
        invisibles = chrome.invisibles ?? chrome.foreground.withAlpha(0.35)
        secondaryCaret = chrome.caret
        heading = theme.style(for: "markup.heading")?.color ?? chrome.foreground
        link = theme.style(for: "markup.link")?.color ?? chrome.foreground
        muted = chrome.foreground.mixed(toward: chrome.background, fraction: 0.4)
        rule = chrome.foreground.mixed(toward: chrome.background, fraction: 0.88, opaque: true)
        codeForeground = chrome.foreground
        codeBackground = (theme.style(for: "markup.raw")?.color ?? chrome.foreground)
            .mixed(toward: chrome.background, fraction: 0.92, opaque: true)
        quoteForeground = chrome.foreground
        quoteBackground = codeBackground
        quoteBorder = rule
    }
}

private extension ThemeColor {
    func withAlpha(_ value: Double) -> ThemeColor {
        ThemeColor(red: red, green: green, blue: blue, alpha: value)
    }

    func mixed(toward background: ThemeColor, fraction: Double, opaque: Bool = false) -> ThemeColor {
        ThemeColor(
            red: red * (1 - fraction) + background.red * fraction,
            green: green * (1 - fraction) + background.green * fraction,
            blue: blue * (1 - fraction) + background.blue * fraction,
            alpha: opaque ? 1 : alpha
        )
    }
}
