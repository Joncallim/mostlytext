import Foundation
@testable import MacDown2
import Testing

@MainActor
@Suite("Example script installation titles")
struct ExampleScriptsTitleTests {
    private static let catalogBundle: Bundle = .main

    private func bundle(_ language: String) throws -> Bundle {
        let url = try #require(Self.catalogBundle.url(forResource: language, withExtension: "lproj"))
        return try #require(Bundle(url: url))
    }

    @Test func actualEnglishCatalogProducesReadableSingularAndPluralMessages() throws {
        let resources = try bundle("en")
        for count in [0, 1, 2, 5] {
            let expected = "Added \(count) Example \(count == 1 ? "Script" : "Scripts")"
            #expect(TextFilterCommands.installedExamplesTitle(
                count: count, bundle: resources, locale: Locale(identifier: "en_US")
            ) == expected)
        }
    }

    @Test(arguments: ["en", "fr", "ja", "pl"])
    func actualLocaleResourcesNeverExposeGrammarMarkup(_ language: String) throws {
        let title = try TextFilterCommands.installedExamplesTitle(
            count: 2, bundle: bundle(language), locale: Locale(identifier: language)
        )
        #expect(!title.contains("^["))
        #expect(!title.contains("inflect:"))
        #expect(title.contains("2"))
    }

    @Test func explicitCatalogSelectionControlsTheInstalledMessage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ExampleTitle-\(UUID())")
        let language = root.appendingPathComponent("en.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: language, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let values = ["^[Added %lld Example Script](inflect: true)": "installation-marker-%lld"]
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            .write(to: language.appendingPathComponent("Localizable.strings"), options: .withoutOverwriting)
        let resources = try #require(Bundle(url: language))
        #expect(TextFilterCommands.installedExamplesTitle(
            count: 2, bundle: resources, locale: Locale(identifier: "en_US")
        ) == "installation-marker-2")
    }
}
