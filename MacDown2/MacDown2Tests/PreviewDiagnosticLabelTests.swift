import Foundation
@testable import MacDown2
import Testing

@Suite("Preview diagnostic accessibility labels")
struct PreviewDiagnosticLabelTests {
    private static let catalogBundle: Bundle = .main

    @Test(arguments: ["en", "fr", "ja", "pl"])
    func compiledCountsUseWholeMessagesAndCatalogPluralForms(_ language: String) throws {
        let url = try #require(Self.catalogBundle.url(forResource: language, withExtension: "lproj"))
        let resources = try #require(Bundle(url: url))
        for count in [0, 1, 2, 5, 12, 22] {
            let suffixes = Self.expectedSuffixes(language: language, count: count)
            #expect(PreviewDiagnosticLabel.error(count: count)
                .message(bundle: resources, locale: Locale(identifier: language)) == "\(count)\(suffixes.error)")
            #expect(PreviewDiagnosticLabel.warning(count: count)
                .message(bundle: resources, locale: Locale(identifier: language)) == "\(count)\(suffixes.warning)")
        }
    }

    private static func expectedSuffixes(language: String, count: Int) -> (error: String, warning: String) {
        switch language {
        case "en":
            return count == 1 ? (" preview error", " preview warning") :
                (" preview errors", " preview warnings")
        case "fr":
            return count < 2 ? (" erreur d'aperçu", " avertissement d'aperçu") :
                (" erreurs d'aperçu", " avertissements d'aperçu")
        case "ja":
            return ("件のプレビューエラー", "件のプレビュー警告")
        case "pl":
            if count == 1 {
                return (" błąd podglądu", " ostrzeżenie podglądu")
            }
            if count == 2 || count == 22 {
                return (" błędy podglądu", " ostrzeżenia podglądu")
            }
            return (" błędów podglądu", " ostrzeżeń podglądu")
        default:
            preconditionFailure("Uncovered test locale: \(language)")
        }
    }

    @Test func explicitResourceBundleControlsBothSeverityLabels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewLabel-\(UUID())")
        let language = root.appendingPathComponent("fr.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: language, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let values = ["%lld preview errors": "error-marker-%lld", "%lld preview warnings": "warning-marker-%lld"]
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            .write(to: language.appendingPathComponent("Localizable.strings"), options: .withoutOverwriting)
        let resources = try #require(Bundle(url: language))
        for count in [1, 5] {
            #expect(PreviewDiagnosticLabel.error(count: count)
                .message(bundle: resources, locale: Locale(identifier: "fr")) == "error-marker-\(count)")
            #expect(PreviewDiagnosticLabel.warning(count: count)
                .message(bundle: resources, locale: Locale(identifier: "fr")) == "warning-marker-\(count)")
        }
    }

    @Test func aMissingCatalogStillProducesAReadableDetail() {
        let empty = Bundle(for: NSObject.self)
        #expect(PreviewDiagnosticLabel.error(count: 5).message(bundle: empty) == "5 preview errors")
        #expect(PreviewDiagnosticLabel.warning(count: 5).message(bundle: empty) == "5 preview warnings")
    }
}
