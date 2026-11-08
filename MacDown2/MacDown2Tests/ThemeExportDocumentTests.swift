import Foundation
@testable import MacDown2
import Testing
import Themes

struct ThemeExportDocumentTests {
    @Test func exportFreezesAdmittedBytesInsteadOfReadingALaterThemeValue() throws {
        var theme = BundledThemes.light
        let file = try ThemeFile(theme: theme)
        let document = try ThemeExportDocument(theme: file)
        theme.name = "Later edit"
        #expect(try document.data == (file.encoded()))
        #expect(try ThemeFile.decode(document.data).displayName != theme.name)
    }

    @Test(arguments: ["../folder:name\\next", "...", "  ", String(repeating: "🌗", count: 100)])
    func suggestedNameIsOneBoundedComponent(_ input: String) {
        let name = ThemeExportDocument.suggestedName(input)
        #expect(!name.isEmpty)
        #expect(name.utf8.count <= 200)
        #expect(!name.hasPrefix("."))
        #expect(!name.contains("/"))
        #expect(!name.contains("\\"))
        #expect(!name.contains(":"))
    }

    @Test func emptySuggestedNameUsesTheSameLocalizedFallbackAsTheExporter() {
        #expect(ThemeExportDocument.suggestedName(String()) == String(localized: "Theme"))
        #expect(ThemeExportDocument.suggestedName("Named theme") == "Named theme")
    }
}
