import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Workspace

@MainActor
@Suite("View locale copy")
struct ViewLocaleCopyTests {
    @Test func panelAndStatusCopyUseThePresentedLocale() throws {
        let (root, bundle) = try makeMultilingualBundle()
        defer { try? FileManager.default.removeItem(at: root) }
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
        let findCopy = FindBarLocalizedCopy(locale: locale, bundle: bundle)
        #expect(findCopy.caseSensitive == "FR_CASE")
        #expect(findCopy.wholeWordShort == "FR_W")
        #expect(findCopy.wholeWord == "FR_WORD")
        #expect(findCopy.regularExpression == "FR_REGEX")
        #expect(findCopy.inSelectionShort == "FR_SEL")
        #expect(findCopy.inSelection == "FR_SELECTION")

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

    @Test func fileFailureCopyUsesThePresentedLocale() throws {
        let (root, bundle) = try makeMultilingualBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let locale = Locale(identifier: "fr")
        let openCases: [(FileStoreError, String)] = [
            (.fileMissing, "FR_OPEN_MISSING"),
            (.permissionDenied, "FR_OPEN_PERMISSION"),
            (.notRegularFile, "FR_NOT_REGULAR"),
            (.invalidURL, "FR_OPEN_LOCATION"),
            (.fileChangedDuringRead, "FR_OPEN_CHANGED"),
            (.encodingDetectionFailed, "FR_OPEN_ENCODING"),
            (.decodingFailed([]), "FR_OPEN_DECODING"),
            (.readFailed(underlying: NSError(domain: "test", code: 1)), "FR_OPEN_READ"),
        ]
        for (error, expected) in openCases {
            #expect(FileOpenFailurePresentation.message(for: error, locale: locale, bundle: bundle)
                == expected)
        }
        let saveCases: [(FileStoreError, String)] = [
            (.writeFailed(underlying: NSError(domain: "test", code: 2)), "FR_SAVE_WRITE"),
            (.permissionDenied, "FR_SAVE_PERMISSION"),
            (.notRegularFile, "FR_NOT_REGULAR"),
            (.invalidURL, "FR_SAVE_LOCATION"),
            (.fileChangedDuringRead, "FR_SAVE_CHANGED"),
            (.fileMissing, "FR_SAVE_MISSING"),
            (.decodingFailed([]), "FR_SAVE_DECODING"),
            (.readFailed(underlying: NSError(domain: "test", code: 3)), "FR_SAVE_READ"),
        ]
        for (error, expected) in saveCases {
            #expect(FileSaveFailurePresentation.message(for: error, locale: locale, bundle: bundle)
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

    @Test func progressAndRecoveryCopyUseThePresentedLocale() throws {
        let (root, bundle) = try makeMultilingualBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let locale = Locale(identifier: "fr")

        #expect(ExportPhase.preparing.label(locale: locale, bundle: bundle) == "FR_PREPARING")
        #expect(ExportPhase.loadingPDF.label(locale: locale, bundle: bundle) == "FR_LOADING_PDF")
        #expect(ExportPhase.cancelling.label(locale: locale, bundle: bundle) == "FR_CANCELLING")
        #expect(FileTreeOperationError.nameEmpty.message(locale: locale, bundle: bundle) == "FR_NAME_REQUIRED")
        #expect(FileTreeOperationError.sourceMissing.message(locale: locale, bundle: bundle) == "FR_ITEM_MISSING")
        #expect(FileTreeOperationError.underlying("authored detail").message(locale: locale, bundle: bundle)
            == "authored detail")
        #expect(WorkspaceError.textNotRepresentableCopy(
            encodingName: "Windows-1252", locale: locale, bundle: bundle
        ) == "FR_ENCODING_Windows-1252")
    }

    private func makeMultilingualBundle() throws -> (URL, Bundle) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-view-locale-\(UUID().uuidString)")
        let french = root.appendingPathComponent("fr.lproj")
        let english = root.appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: french, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        let translations = frenchTranslations
        try writeTranslations(translations, in: french)
        try writeTranslations(translations.mapValues { $0.replacingOccurrences(of: "FR_", with: "EN_") },
                              in: english)
        return try (root, #require(Bundle(url: root)))
    }

    private var frenchTranslations: [String: String] {
        let encodingKey = "This text cannot be saved as %@ without losing characters. " +
            "Nothing was changed; choose another encoding, or delete an invisible byte-order-mark character " +
            "(U+FEFF or U+FFFE) at the very start of the text."
        return [
            "HTML": "FR_HTML",
            "Self-contained HTML": "FR_SELF_CONTAINED",
            "PDF": "FR_PDF",
            "Embeds the stylesheet and every image into one file that opens anywhere.": "FR_EMBED_HTML",
            "Embeds every image and prints through the macOS render system.": "FR_EMBED_PDF",
            "Source": "FR_SOURCE",
            "Rendered": "FR_RENDERED",
            "Outline": "FR_OUTLINE",
            "Case Sensitive": "FR_CASE",
            "W": "FR_W",
            "Whole Word": "FR_WORD",
            "Regular Expression": "FR_REGEX",
            "Sel": "FR_SEL",
            "In Selection": "FR_SELECTION",
            "The backing file is unavailable. Save As to keep this copy.": "FR_UNAVAILABLE",
            "MostlyText cannot access the backing file. Save As to keep this copy.": "FR_PERMISSION",
            "The backing path is no longer a regular file. Save As to keep this copy.": "FR_NOT_FILE",
            "MostlyText cannot safely identify the moved file. Save As to keep this copy.": "FR_AMBIGUOUS",
            "The backing file could not be read safely. Save As to keep this copy.": "FR_READ_FAILED",
            "The file could not be found.": "FR_OPEN_MISSING",
            "MostlyText does not have permission to read this file.": "FR_OPEN_PERMISSION",
            "This is not a regular file.": "FR_NOT_REGULAR",
            "This is not a valid file location.": "FR_OPEN_LOCATION",
            "The file changed while it was being read. Try again.": "FR_OPEN_CHANGED",
            "The file's text encoding could not be determined.": "FR_OPEN_ENCODING",
            "The file's contents could not be decoded.": "FR_OPEN_DECODING",
            "The file could not be read.": "FR_OPEN_READ",
            "The file could not be written.": "FR_SAVE_WRITE",
            "MostlyText does not have permission to write this file.": "FR_SAVE_PERMISSION",
            "This is not a valid save location.": "FR_SAVE_LOCATION",
            "The file changed on disk while saving. Try again.": "FR_SAVE_CHANGED",
            "The file could not be found. It may have been moved, renamed, or deleted.": "FR_SAVE_MISSING",
            "The file's contents could not be verified after saving.": "FR_SAVE_DECODING",
            "A competing version was preserved separately.": "FR_SAVE_COMPETING",
            "The file could not be verified after saving.": "FR_SAVE_READ",
            "Preparing export…": "FR_PREPARING",
            "Loading PDF content…": "FR_LOADING_PDF",
            "Cancelling export…": "FR_CANCELLING",
            "A name is required.": "FR_NAME_REQUIRED",
            "The item no longer exists.": "FR_ITEM_MISSING",
            encodingKey: "FR_ENCODING_%@",
        ]
    }

    private func writeTranslations(_ translations: [String: String], in folder: URL) throws {
        let strings = translations.sorted { $0.key < $1.key }
            .map { "\"\($0.key)\" = \"\($0.value)\";" }.joined(separator: "\n")
        try strings.write(to: folder.appendingPathComponent("Localizable.strings"),
                          atomically: true, encoding: .utf8)
    }
}
