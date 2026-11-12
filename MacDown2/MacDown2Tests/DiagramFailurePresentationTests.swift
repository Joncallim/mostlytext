import Foundation
@testable import MacDown2
import Testing

@Suite("Diagram failure localisation")
struct DiagramFailurePresentationTests {
    private static let catalogBundle: Bundle = .main

    private func bundle(_ language: String) throws -> Bundle {
        let url = try #require(Self.catalogBundle.url(forResource: language, withExtension: "lproj"))
        return try #require(Bundle(url: url))
    }

    @Test(arguments: ["en", "fr", "ja", "pl"])
    func actualCompiledCatalogContainsAllSharedFailureStates(_ language: String) throws {
        let cases: [(DiagramFailurePresentation, String)] = [
            (.noPreviewImage, "no preview image was produced"),
            (.timedOut, "rendering timed out"),
            (.rendererUnavailable, "renderer unavailable"),
        ]
        let resources = try bundle(language)
        for (failure, expected) in cases {
            #expect(resources.localizedString(forKey: expected, value: "missing-entry", table: nil) != "missing-entry")
            #expect(failure.message(bundle: resources, locale: Locale(identifier: language)) == expected)
        }
    }

    @Test(arguments: ["en", "fr", "ja", "pl"])
    func actualCompiledCatalogSelectsCountFormsWithoutNarrowingTheByteCount(_ language: String) throws {
        let resources = try bundle(language)
        for count in [0, 1, 2, 5, 12, 22, Int.max] {
            let maximums = [
                "en": "9,223,372,036,854,775,807", "ja": "9,223,372,036,854,775,807",
                "fr": "9\u{202F}223\u{202F}372\u{202F}036\u{202F}854\u{202F}775\u{202F}807",
                "pl": "9\u{00A0}223\u{00A0}372\u{00A0}036\u{00A0}854\u{00A0}775\u{00A0}807",
            ]
            let number = count == Int.max ? try #require(maximums[language]) : String(count)
            let expected = Self.expectedByteCount(language: language, count: count, number: number)
            #expect(DiagramFailurePresentation.outputTooLarge(byteCount: count)
                .message(bundle: resources, locale: Locale(identifier: language)) == expected)
        }
    }

    private static func expectedByteCount(language: String, count: Int, number: String) -> String {
        switch language {
        case "en":
            return "rendered output too large (\(number) \(count == 1 ? "byte" : "bytes"))"
        case "fr":
            return "sortie générée trop volumineuse (\(number) \(count < 2 ? "octet" : "octets"))"
        case "ja":
            return "描画結果が大きすぎます（\(number)バイト）"
        case "pl":
            let unit = if count == 1 {
                "bajt"
            } else if count == 2 || count == 22 {
                "bajty"
            } else {
                "bajtów"
            }
            return "Wynik renderowania jest zbyt duży (\(number) \(unit))"
        default:
            preconditionFailure("Uncovered test locale: \(language)")
        }
    }

    @Test func aMissingCatalogPreservesTheExistingEnglishFallback() {
        let empty = Bundle(for: NSObject.self)
        #expect(DiagramFailurePresentation.noPreviewImage.message(bundle: empty) == "no preview image was produced")
        #expect(DiagramFailurePresentation.timedOut.message(bundle: empty) == "rendering timed out")
        #expect(DiagramFailurePresentation.rendererUnavailable.message(bundle: empty) == "renderer unavailable")
        #expect(DiagramFailurePresentation.outputTooLarge(byteCount: 123)
            .message(bundle: empty) == "rendered output too large (123 bytes)")
    }

    @Test func anExplicitBundleRoutesEveryKnownStateWithoutFallingBackToMain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiagramCopy-\(UUID())")
        let language = root.appendingPathComponent("fr.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: language, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let values = [
            "no preview image was produced": "fixture image marker",
            "rendering timed out": "fixture timeout marker",
            "renderer unavailable": "fixture unavailable marker",
            "rendered output too large (%lld bytes)": "fixture size marker %lld",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try data.write(to: language.appendingPathComponent("Localizable.strings"), options: .withoutOverwriting)
        let resources = try #require(Bundle(url: language))
        let locale = Locale(identifier: "fr")
        #expect(DiagramFailurePresentation.noPreviewImage.message(bundle: resources, locale: locale)
            == "fixture image marker")
        #expect(DiagramFailurePresentation.timedOut.message(bundle: resources, locale: locale)
            == "fixture timeout marker")
        #expect(DiagramFailurePresentation.rendererUnavailable.message(bundle: resources, locale: locale)
            == "fixture unavailable marker")
        #expect(DiagramFailurePresentation.outputTooLarge(byteCount: 42).message(bundle: resources, locale: locale)
            == "fixture size marker 42")
    }
}
