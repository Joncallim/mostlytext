import FileCore
import Foundation
import Highlighting
@testable import MacDown2
import Testing

@MainActor
@Suite("View locale copy")
struct ViewLocaleCopyTests {
    @Test func panelAndStatusCopyUseThePresentedLocale() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-view-locale-\(UUID().uuidString)")
        let french = root.appendingPathComponent("fr.lproj")
        try FileManager.default.createDirectory(at: french, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let translations = [
            "HTML": "FR_HTML",
            "Self-contained HTML": "FR_SELF_CONTAINED",
            "PDF": "FR_PDF",
            "Embeds the stylesheet and every image into one file that opens anywhere.": "FR_EMBED_HTML",
            "Embeds every image and prints through the macOS render system.": "FR_EMBED_PDF",
            "Source": "FR_SOURCE",
            "Rendered": "FR_RENDERED",
            "Outline": "FR_OUTLINE",
            "The backing file is unavailable. Save As to keep this copy.": "FR_UNAVAILABLE",
            "MostlyText cannot access the backing file. Save As to keep this copy.": "FR_PERMISSION",
            "The backing path is no longer a regular file. Save As to keep this copy.": "FR_NOT_FILE",
            "MostlyText cannot safely identify the moved file. Save As to keep this copy.": "FR_AMBIGUOUS",
            "The backing file could not be read safely. Save As to keep this copy.": "FR_READ_FAILED",
        ]
        let strings = translations.sorted { $0.key < $1.key }
            .map { "\"\($0.key)\" = \"\($0.value)\";" }.joined(separator: "\n")
        try strings.write(to: french.appendingPathComponent("Localizable.strings"),
                          atomically: true, encoding: .utf8)
        let bundle = try #require(Bundle(url: root))
        let locale = Locale(identifier: "fr")

        #expect(ExportFormatOption.standaloneHTML.title(locale: locale, bundle: bundle) == "FR_HTML")
        #expect(ExportFormatOption.selfContainedHTML.title(locale: locale, bundle: bundle) == "FR_SELF_CONTAINED")
        #expect(ExportFormatOption.pdf.title(locale: locale, bundle: bundle) == "FR_PDF")
        #expect(ExportFormatOption.standaloneHTML.explanation(locale: locale, bundle: bundle) == nil)
        #expect(ExportFormatOption.selfContainedHTML.explanation(locale: locale, bundle: bundle) == "FR_EMBED_HTML")
        #expect(ExportFormatOption.pdf.explanation(locale: locale, bundle: bundle) == "FR_EMBED_PDF")
        #expect(HTMLPreviewPane.modeLabel(.source, locale: locale, bundle: bundle) == "FR_SOURCE")
        #expect(HTMLPreviewPane.modeLabel(.rendered, locale: locale, bundle: bundle) == "FR_RENDERED")
        #expect(HTMLPreviewPane.modeLabel(.outline, locale: locale, bundle: bundle) == "FR_OUTLINE")

        let cases: [(FileBackingIssue, String)] = [
            (.missingOrMoved, "FR_UNAVAILABLE"),
            (.parentUnavailable, "FR_UNAVAILABLE"),
            (.permissionDenied, "FR_PERMISSION"),
            (.notRegularFile, "FR_NOT_FILE"),
            (.ambiguousMove, "FR_AMBIGUOUS"),
            (.moveCollidesWithOpenDocument, "FR_AMBIGUOUS"),
            (.readFailed("authored detail"), "FR_READ_FAILED"),
        ]
        for (issue, expected) in cases {
            #expect(ExternalFileStatusView.unavailableCopy(for: issue, locale: locale, bundle: bundle)
                == expected)
        }
    }

    @Test func reducedHighlightingHelpFormatsTheThresholdForThePresentedLocale() throws {
        let state = HighlightingState(
            requestedLanguageID: "markdown",
            mode: .visibleOnly(.documentTooLarge(limitUTF16Units: 8 * 1024))
        )
        let note = try #require(ReducedHighlightingNote(state))
        let french = Locale(identifier: "fr")
        let english = Locale(identifier: "en_US")
        let frenchNumber = note.restoreAtOrBelowUTF16Units.formatted(.number.locale(french))
        let englishNumber = note.restoreAtOrBelowUTF16Units.formatted(.number.locale(english))
        #expect(frenchNumber != englishNumber)
        #expect(note.explanation(locale: french).contains(frenchNumber))
        #expect(note.explanation(locale: english).contains(englishNumber))
    }
}
