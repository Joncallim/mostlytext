import Foundation
import Testing
@testable import Themes

struct ResolvedPresentationPaletteTests {
    @Test func customSemanticColorsDoNotChangeWithAppearance() {
        var theme = BundledThemes.light
        let link = ThemeColor(red: 0.12, green: 0.23, blue: 0.34)
        theme.tokenStyles["markup.link"] = TokenStyle(color: link)
        let light = ResolvedPresentationPalette(theme: theme)
        theme.appearance = .dark
        let dark = ResolvedPresentationPalette(theme: theme)
        #expect(light.link == link)
        #expect(dark.link == link)
        #expect(light.codeBackground == dark.codeBackground)
    }

    @Test func missingTokensUseTheDocumentForeground() {
        var theme = BundledThemes.light
        theme.tokenStyles = [:]
        let palette = ResolvedPresentationPalette(theme: theme)
        #expect(palette.link == theme.chrome.foreground)
        #expect(palette.heading == theme.chrome.foreground)
        #expect(palette.codeForeground == theme.chrome.foreground)
        #expect(palette.quoteForeground == theme.chrome.foreground)
    }

    @Test func explicitChromeRolesSurviveResolution() {
        var theme = BundledThemes.dark
        let explicit = ThemeColor(red: 0.2, green: 0.5, blue: 0.6, alpha: 0.3)
        theme.chrome.invisibles = explicit
        theme.chrome.currentLine = explicit
        let palette = ResolvedPresentationPalette(theme: theme)
        #expect(palette.invisibles == explicit)
        #expect(palette.currentLine == explicit)
        #expect(palette.selectionBackground == theme.chrome.selection)
        #expect(palette.caret == theme.chrome.caret)
    }

    @Test func catalogHasFourLightAndFourDarkDistinctThemes() {
        let all = BundledThemes.all
        #expect(all.count >= 8)
        #expect(all.filter { $0.appearance == .light }.count >= 4)
        #expect(all.filter { $0.appearance == .dark }.count >= 4)
        #expect(Set(all.map(\.id)).count == all.count)
        for first in all.indices {
            for second in all.indices where first < second {
                #expect(all[first].chrome != all[second].chrome || all[first].tokenStyles != all[second].tokenStyles,
                        "Different names must not disguise duplicate palettes")
            }
        }
        #expect(BundledThemes.light.id == "tomorrow-light")
        #expect(BundledThemes.light.name == "GitHub Light")
        #expect(BundledThemes.dark.id == "tomorrow-dark")
    }

    @Test func bundledCoreRolesMeetReadabilityTargets() {
        for theme in BundledThemes.all {
            let palette = ResolvedPresentationPalette(theme: theme)
            #expect(palette.background.alpha == 1)
            #expect(palette.codeBackground.alpha == 1)
            for (role, foreground, background) in [
                ("body", palette.foreground, palette.background),
                ("link", palette.link, palette.background),
                ("code", palette.codeForeground, palette.codeBackground),
            ] {
                #expect(contrast(foreground, on: background) >= 4.5, "\(theme.name) \(role)")
                let channels = [
                    foreground.red, foreground.green, foreground.blue, foreground.alpha,
                    background.red, background.green, background.blue, background.alpha,
                ]
                for channel in channels {
                    #expect(channel.isFinite && (0 ... 1).contains(channel))
                }
            }
            if theme.id.hasPrefix("high-contrast-") {
                #expect(contrast(palette.foreground, on: palette.background) >= 7)
            }
        }
    }

    @Test func contrastCalculationHasBlackWhiteControls() {
        let white = ThemeColor(red: 1, green: 1, blue: 1)
        let black = ThemeColor(red: 0, green: 0, blue: 0)
        #expect(abs(contrast(black, on: white) - 21) < 0.0001)
        #expect(abs(contrast(white, on: black) - 21) < 0.0001)
        #expect(abs(contrast(white, on: white) - 1) < 0.0001)
    }

    @Test func minimalDarkFallbackHasTheRequestedAppearance() {
        let theme = BundledThemes.minimalTheme(id: "midnight", appearance: .dark)
        #expect(theme.appearance == .dark)
        #expect(theme.chrome.background == ThemeColor(red: 0, green: 0, blue: 0))
        #expect(contrast(theme.chrome.foreground, on: theme.chrome.background) >= 7)
    }

    private func contrast(_ foreground: ThemeColor, on background: ThemeColor) -> Double {
        func luminance(_ color: ThemeColor) -> Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        }
        let visible = ThemeColor(
            red: foreground.red * foreground.alpha + background.red * (1 - foreground.alpha),
            green: foreground.green * foreground.alpha + background.green * (1 - foreground.alpha),
            blue: foreground.blue * foreground.alpha + background.blue * (1 - foreground.alpha)
        )
        let first = luminance(visible)
        let second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
