import Contributions
import ExportService
import Foundation
@testable import MacDown2
import Testing

struct ExportContributionSafetyTests {
    private func diagnostic(id: UUID) -> ContributionDiagnostic {
        .init(severity: .warning, message: "bounded output unavailable", sourceRange: 2 ..< 5,
              sourceID: id, sourceOffset: 3, code: "math.resourceLimit", preventsPublication: true)
    }

    @Test func fatalAdmissionPreservesOriginalMetadataForContentAndStandaloneResults() {
        let id = UUID()
        let diagnostic = diagnostic(id: id)
        let content = ContributionContent(
            sourceRange: 2 ..< 5,
            placement: .inline,
            representation: .html("<code>$x$</code>")
        )
        for destination in [ContributionDestination.htmlExport, .pdfExport] {
            for body in [nil, Optional(content)] {
                let result = ContributionResult(
                    contributionID: "math",
                    content: body,
                    sourceGeneration: 9,
                    diagnostics: [diagnostic]
                )
                let adapted = ExportContributionAdapter.adapt([result], destination: destination)
                let actual = adapted.standaloneDiagnostics + adapted.contributions.flatMap(\.diagnostics)
                #expect(actual.count == 1)
                #expect(actual.first?.sourceRange == 2 ..< 5 && actual.first?.sourceOffset == 3)
                #expect(actual.first?.sourceID == id && actual.first?.code == "math.resourceLimit")
                #expect(actual.first?.preventsPublication == true)
                #expect(throws: ExportError.self) { try adapted.requirePublication() }
            }
        }
    }

    @Test func unsupportedContentCannotDiscardAFatalObservation() {
        let content = ContributionContent(
            sourceRange: 2 ..< 5,
            placement: .inline,
            representation: .html("<code>$x$</code>")
        )
        let id = UUID()
        let result = ContributionResult(
            contributionID: "math",
            content: content,
            sourceGeneration: 9,
            diagnostics: [diagnostic(id: id)]
        )
        let adapted = ExportContributionAdapter.adapt([result], destination: .nativePreview)
        #expect(adapted.contributions.isEmpty)
        #expect(adapted.standaloneDiagnostics.first?.sourceID == id)
        #expect(adapted.standaloneDiagnostics.first?.preventsPublication == true)
        #expect(throws: ExportError.self) { try adapted.requirePublication() }
    }

    @Test func ordinaryDerivedErrorsKeepTheirExistingNonfatalDisposition() throws {
        let content = ContributionContent(
            sourceRange: 0 ..< 3,
            placement: .inline,
            representation: .html("<span>rejected</span>")
        )
        let result = ContributionResult(contributionID: "other", content: content, sourceGeneration: 1,
                                        diagnostics: [.init(severity: .error, message: "ordinary derived failure")])
        let adapted = ExportContributionAdapter.adapt([result], destination: .htmlExport)
        #expect(adapted.contributions.first?.diagnostics.first?.severity == .error)
        #expect(adapted.contributions.first?.diagnostics.first?.preventsPublication == false)
        try adapted.requirePublication()
    }
}
