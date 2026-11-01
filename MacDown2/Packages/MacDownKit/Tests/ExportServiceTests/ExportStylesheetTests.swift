import ExportService
import Testing
import Themes

/// The bundled structural stylesheet and the theme variable block it pairs with.
struct ExportStylesheetTests {
    @Test func structuralSheetOnlyDeclaresColorSchemeForPrint() throws {
        // On screen the theme owns `color-scheme`; a structural default would
        // win over it and make dark exports render light-mode UA widgets. Print
        // is the one place the structural sheet may override the theme.
        let css = ExportThemeStylesheet.structural
        let firstDeclaration = try #require(css.range(of: "color-scheme:"))
        let printBlock = try #require(css.range(of: "@media print {"))
        #expect(printBlock.lowerBound < firstDeclaration.lowerBound)
    }

    @Test func taskListItemsAreMatchedByTheirCheckbox() {
        // cmark-gfm's tasklist extension emits no class, so a `.task-list-item`
        // selector would never match anything it renders.
        #expect(ExportThemeStylesheet.structural.contains("input[type=\"checkbox\"]"))
        #expect(!ExportThemeStylesheet.structural.contains("li.task-list-item"))
    }

    @Test func printRulesExistForThePDFPass() {
        let css = ExportThemeStylesheet.structural
        #expect(css.contains("@media print"))
        #expect(css.contains("page-break-inside: avoid"))
        #expect(css.contains("orphans"))
    }

    @Test func codeBackgroundStaysCloseToThePageBackground() {
        // A code block is a surface, not a highlight: its backdrop must read as
        // a tint of the page, never as the raw-markup colour at full strength.
        for theme in [BundledThemes.light, BundledThemes.dark] {
            let variables = ExportThemeStylesheet.variables(for: theme)
            let background = try? channels(of: "--md-background", in: variables)
            let codeBackground = try? channels(of: "--md-code-bg", in: variables)
            guard let background, let codeBackground else {
                Issue.record("\(theme.name): could not read the colour variables")
                continue
            }
            let distance = zip(background, codeBackground).map { pair in abs(pair.0 - pair.1) }.max() ?? 255
            #expect(distance < 40, "\(theme.name): code backdrop is \(distance) away from the page")
        }
    }

    @Test func semanticColorsMatchTheSharedPaletteForEveryBundledTheme() throws {
        for theme in BundledThemes.all {
            let palette = ResolvedPresentationPalette(theme: theme)
            let variables = ExportThemeStylesheet.variables(for: theme)
            for (name, color) in [
                ("--md-heading", palette.heading), ("--md-link", palette.link),
                ("--md-muted", palette.muted), ("--md-rule", palette.rule),
                ("--md-code-bg", palette.codeBackground),
            ] {
                let expected = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
                #expect(try channels(of: name, in: variables) == expected, "\(theme.name): \(name)")
            }
        }
    }

    /// The RGB channels of a `#rrggbb` custom-property value.
    private func channels(of name: String, in css: String) throws -> [Int] {
        let line = try #require(css.split(separator: "\n").first { $0.contains(name) })
        let hex = line.drop { $0 != "#" }.dropFirst().prefix(6)
        try #require(hex.count == 6, "\(name) is not a #rrggbb value")
        return try stride(from: 0, to: 6, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return try #require(Int(hex[start ..< end], radix: 16))
        }
    }
}
