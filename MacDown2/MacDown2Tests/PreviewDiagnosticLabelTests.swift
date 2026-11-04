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
            let singular = language == "fr" ? count < 2 : language != "ja" && count == 1
            let error = "\(count) preview \(singular ? "error" : "errors")"
            let warning = "\(count) preview \(singular ? "warning" : "warnings")"
            #expect(PreviewDiagnosticLabel.error(count: count)
                .message(bundle: resources, locale: Locale(identifier: language)) == error)
            #expect(PreviewDiagnosticLabel.warning(count: count)
                .message(bundle: resources, locale: Locale(identifier: language)) == warning)
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
