@testable import ExportService
import Foundation
import Testing

@Suite("cmark failure localisation")
struct CMarkErrorLocalizationTests {
    private var cases: [(CMarkGFM.CMarkError, String)] {
        [
            (.parserCreationFailed, "cmark could not create a parser"),
            (.parseProducedNoDocument, "cmark produced no document"),
            (.renderFailed, "cmark could not render HTML"),
        ]
    }

    @Test func diagnosticDescriptionsRemainStable() {
        for (error, expected) in cases {
            #expect(error.description == expected)
            #expect(String(describing: error) == expected)
        }
    }

    @Test func existingEnglishErrorDetailsRemainReadable() {
        for (error, expected) in cases {
            #expect(error.errorDescription == expected)
            #expect(error.localizedDescription == expected)
        }
    }

    @Test func theExportWrapperPreservesTheUnderlyingLocalizedDetail() {
        for (error, expected) in cases {
            let wrapper = ExportError.renderFailed(underlying: error)
            #expect(wrapper.errorDescription?.hasSuffix(expected) == true)
        }
    }
}
