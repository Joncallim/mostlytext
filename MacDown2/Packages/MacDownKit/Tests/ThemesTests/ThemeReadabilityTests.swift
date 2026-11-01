import Testing
@testable import Themes

struct ThemeReadabilityTests {
    @Test func equalForegroundAndCanvasWarnWithoutInvalidatingAUserTheme() throws {
        var theme = BundledThemes.light
        theme.chrome.foreground = theme.chrome.background
        let file = try ThemeFile(theme: theme)
        #expect(ThemeReadability(theme: file.theme).hasLowContrastText)
        #expect(ThemeReadability(theme: file.theme).bodyContrast == 1)
    }

    @Test func selectedTextUsesItsActualCompositedBackground() {
        var theme = BundledThemes.light
        theme.chrome.background = ThemeColor(red: 1, green: 1, blue: 1)
        theme.chrome.foreground = ThemeColor(red: 0, green: 0, blue: 0)
        theme.chrome.selection = ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)
        #expect(ThemeReadability(theme: theme).selectionContrast == 21)
        theme.chrome.selection.alpha = 1
        #expect(ThemeReadability(theme: theme).selectionContrast == 1)
        #expect(ThemeReadability(theme: theme).hasLowContrastText)
    }

    @Test func bundledTextRolesRemainReadable() {
        for theme in BundledThemes.all {
            let report = ThemeReadability(theme: theme)
            #expect(report.bodyContrast >= 4.5)
            #expect(report.linkContrast >= 4.5)
            #expect(report.codeContrast >= 4.5)
        }
    }
}
