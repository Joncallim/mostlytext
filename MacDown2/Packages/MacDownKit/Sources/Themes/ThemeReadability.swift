import Foundation

/// Core text readability warnings, not a certification or an import refusal.
public struct ThemeReadability: Sendable, Equatable {
    public let bodyContrast: Double
    public let linkContrast: Double
    public let codeContrast: Double
    public let selectionContrast: Double

    public var hasLowContrastText: Bool {
        [bodyContrast, linkContrast, codeContrast, selectionContrast].contains { $0 < 4.5 }
    }

    public init(theme: Theme) {
        let palette = ResolvedPresentationPalette(theme: theme)
        bodyContrast = Self.contrast(palette.foreground, on: palette.background)
        linkContrast = Self.contrast(palette.link, on: palette.background)
        codeContrast = Self.contrast(palette.codeForeground, on: palette.codeBackground)
        selectionContrast = Self.contrast(palette.selectionForeground,
                                          on: Self.composite(palette.selectionBackground, over: palette.background))
    }

    private static func contrast(_ foreground: ThemeColor, on background: ThemeColor) -> Double {
        let visible = composite(foreground, over: background)
        func luminance(_ color: ThemeColor) -> Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        }
        let first = luminance(visible)
        let second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func composite(_ foreground: ThemeColor, over background: ThemeColor) -> ThemeColor {
        ThemeColor(red: foreground.red * foreground.alpha + background.red * (1 - foreground.alpha),
                   green: foreground.green * foreground.alpha + background.green * (1 - foreground.alpha),
                   blue: foreground.blue * foreground.alpha + background.blue * (1 - foreground.alpha))
    }
}
