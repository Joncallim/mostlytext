import FileCore
import Foundation
import Testing

@Suite("View localization bundle")
struct ViewLocalizationBundleTests {
    @Test func selectsTheViewsLanguageFromAMultilingualBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-bundle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (language, value) in [("en", "EN_COPY"), ("fr", "FR_COPY")] {
            let folder = root.appendingPathComponent("\(language).lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "\"Visible copy\" = \"\(value)\";".write(
                to: folder.appendingPathComponent("Localizable.strings"),
                atomically: true,
                encoding: .utf8
            )
        }
        let bundle = try #require(Bundle(url: root))
        let french = Locale(identifier: "fr-CA")
        let selected = ViewLocalizationBundle.resolve(locale: french, in: bundle)
        #expect(String(localized: "Visible copy", bundle: selected, locale: french) == "FR_COPY")
        let english = Locale(identifier: "en-US")
        let selectedEnglish = ViewLocalizationBundle.resolve(locale: english, in: bundle)
        #expect(String(localized: "Visible copy", bundle: selectedEnglish, locale: english) == "EN_COPY")
    }
}
