import Foundation
@testable import MacDown2
import Testing

@MainActor
@Suite("PDF failure localisation")
struct PDFErrorLocalizationTests {
    private static let catalogBundle: Bundle = .main

    private var snapshots: [(PDFSnapshotFallback.FallbackError, String)] {
        [
            (.invalidSnapshot, "WebKit did not produce a readable PDF snapshot."),
            (.invalidGeometry, "WebKit produced a PDF with unsupported page dimensions."),
            (.tooManyPages, "The document needs more PDF pages than this export can safely create."),
            (.tooLarge, "The PDF would exceed the current export size limit."),
            (.cannotWrite, "The PDF could not be written to a temporary file."),
            (.timedOut, "WebKit took too long to prepare the PDF."),
        ]
    }

    private var prints: [(PDFExportAdapter.PDFExportError, String)] {
        [
            (.invalidPDFOutput, "The printed document was not a readable PDF."),
            (.noPDFOutput, "The macOS print system did not write a PDF."),
            (.pdfTooLarge, "The PDF exceeds the current export size limit."),
            (.printConfigurationFailed, "The macOS print system did not accept the PDF destination."),
            (.printOperationFailed, "The macOS print system could not produce the PDF."),
            (.pageLoadTimedOut, "Laying the document out for printing took too long."),
        ]
    }

    @Test func actualErrorValuesPreserveTheirExistingEnglishDescriptionsAndGuidance() {
        for (error, expected) in snapshots {
            #expect(error.errorDescription == expected)
            #expect(error.recoverySuggestion
                == "The prior output was left unchanged. Try a shorter document or export as HTML.")
        }
        for (error, expected) in prints {
            #expect(error.errorDescription == expected)
            let guidance = switch error {
            case .pageLoadTimedOut: "Try again, or split very large documents before exporting."
            default: "Try exporting as HTML, or print the document from the preview."
            }
            #expect(error.recoverySuggestion == guidance)
        }
    }

    @Test(arguments: ["en", "fr", "ja", "pl"])
    func actualCompiledCatalogContainsEveryPDFErrorAndRecoveryKey(_ language: String) throws {
        let url = try #require(Self.catalogBundle.url(forResource: language, withExtension: "lproj"))
        let resources = try #require(Bundle(url: url))
        let keys = snapshots.map(\.1) + prints.map(\.1) + [
            "The prior output was left unchanged. Try a shorter document or export as HTML.",
            "Try again, or split very large documents before exporting.",
            "Try exporting as HTML, or print the document from the preview.",
        ]
        for key in keys {
            #expect(resources.localizedString(forKey: key, value: "missing-entry", table: nil) != "missing-entry")
        }
    }
}
