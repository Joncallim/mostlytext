import Foundation
@testable import MacDown2
import Testing

@Suite("Export diagnostic localisation")
struct ExportDiagnosticPresentationTests {
    private static let catalogBundle: Bundle = .main

    private func bundle(_ language: String) throws -> Bundle {
        let url = try #require(Self.catalogBundle.url(forResource: language, withExtension: "lproj"))
        return try #require(Bundle(url: url))
    }

    @Test(arguments: ["en", "fr", "ja", "pl"])
    func actualCompiledCatalogChoosesTitlePluralForms(_ language: String) throws {
        let counts = [0, 1, 2, 5, 12, 22]
        let expected: [String] = switch language {
        case "fr": counts.map { "Exporté avec \($0) \($0 < 2 ? "problème" : "problèmes")" }
        case "ja": counts.map { "\($0)件の問題を伴って書き出しました" }
        case "pl": counts.map { "Wyeksportowano z \($0) \($0 == 1 ? "problemem" : "problemami")" }
        default: counts.map { "Exported with \($0) \($0 == 1 ? "issue" : "issues")" }
        }
        let bundle = try bundle(language)
        for (count, title) in zip(counts, expected) {
            let presentation = ExportDiagnosticPresentation(
                messages: Array(repeating: "literal", count: count), bundle: bundle,
                locale: Locale(identifier: language)
            )
            #expect(presentation.title == title)
        }
    }

    @Test(arguments: ["en", "fr", "ja", "pl"])
    func actualCompiledCatalogChoosesOmittedCountPluralForms(_ language: String) throws {
        let counts = [1, 2, 5, 12, 22]
        let expected: [String] = switch language {
        case "fr": counts.map { "…et \($0) \($0 == 1 ? "autre problème" : "autres problèmes")." }
        case "ja": counts.map { "…ほか\($0)件の問題。" }
        case "pl":
            [
                "…i jeszcze 1 problem.",
                "…i jeszcze 2 problemy.",
                "…i jeszcze 5 problemów.",
                "…i jeszcze 12 problemów.",
                "…i jeszcze 22 problemy.",
            ]
        default: counts.map { "…and \($0) more \($0 == 1 ? "issue" : "issues")." }
        }
        let bundle = try bundle(language)
        for (count, summary) in zip(counts, expected) {
            let presentation = ExportDiagnosticPresentation(
                messages: Array(repeating: "literal", count: count + 6), bundle: bundle,
                locale: Locale(identifier: language)
            )
            #expect(presentation.body == Array(repeating: "literal", count: 6).joined(separator: "\n") + "\n" + summary)
        }
    }

    @Test func sixMessageBoundaryPreservesOrderAndLiteralText() throws {
        let messages = ["α %@", "<source>", "🧑🏽‍💻", "line\nbreak", "5%", "sixth"]
        let bundle = try bundle("en")
        for count in 0 ... 6 {
            let shown = Array(messages.prefix(count))
            let presentation = ExportDiagnosticPresentation(
                messages: shown,
                bundle: bundle,
                locale: Locale(identifier: "en")
            )
            #expect(presentation.body == shown.joined(separator: "\n"))
        }
        let overflow = ExportDiagnosticPresentation(
            messages: messages + ["hidden source"], bundle: bundle, locale: Locale(identifier: "en")
        )
        #expect(overflow.body == messages.joined(separator: "\n") + "\n…and 1 more issue.")
        #expect(!overflow.body.contains("hidden source"))
    }
}
