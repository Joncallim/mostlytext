import Foundation
@testable import MacDown2
import Testing
import Themes

@Test func highContrastPickerLabelsUseTheCompiledAppCatalogWithoutChangingThemeData() throws {
    let frenchURL = try #require(Bundle.main.url(forResource: "fr", withExtension: "lproj"))
    let french = try #require(Bundle(url: frenchURL))
    let light = try #require(BundledThemes.all.first { $0.id == "high-contrast-light" })
    let dark = try #require(BundledThemes.all.first { $0.id == "high-contrast-dark" })

    #expect(ThemePickerDisplayName.name(for: light, bundle: french) == "Contraste élevé (clair)")
    #expect(ThemePickerDisplayName.name(for: dark, bundle: french) == "Contraste élevé (sombre)")
    #expect(ThemePickerDisplayName.menuName(for: light, selectedID: light.id, bundle: french)
        == "✓ Contraste élevé (clair)")
    let lightFile = try ThemeFile(theme: light)
    let darkFile = try ThemeFile(theme: dark)
    #expect(lightFile.displayName == "High Contrast Light")
    #expect(darkFile.displayName == "High Contrast Dark")

    for theme in BundledThemes.all where theme.id != light.id && theme.id != dark.id {
        #expect(ThemePickerDisplayName.name(for: theme, bundle: french) == theme.name)
    }
    let imported = lightFile.theme
    #expect(imported.id != light.id)
    #expect(ThemePickerDisplayName.name(for: imported, bundle: french) == imported.name)
    #expect(ThemePickerDisplayName.menuName(for: imported, selectedID: light.id, bundle: french)
        == "    High Contrast Light")
}
