import ExportService
import Foundation
import Testing

struct FatalDerivedPublicationTests {
    private func contribution(fatal: Bool) -> ExportDerivedContribution {
        let diagnostic = ExportDiagnostic(
            severity: fatal ? .warning : .error, message: "source fallback unavailable",
            sourceRange: 0 ..< 3, sourceID: UUID(), sourceOffset: 1,
            code: "math.resourceLimit", preventsPublication: fatal
        )
        return .init(sourceRange: 0 ..< 3, placement: .inline, html: "<span>DERIVED_CONTENT</span>",
                     sourceGeneration: 1, diagnostics: [diagnostic])
    }

    @Test func everyPreparationTargetRefusesAFatalDerivedDiagnosticEvenIfItsSeverityIsWarning() async throws {
        let contribution = contribution(fatal: true)
        let source = "$x$"
        let request = ExportRequest(text: source, sourceGeneration: 1, theme: ExportTestSupport.lightTheme(),
                                    contributions: [contribution])
        for target in [
            ExportTarget.html(url: URL(fileURLWithPath: "/tmp/math-fatal.html"), mode: .standalone(style: .embedded)),
            .html(url: URL(fileURLWithPath: "/tmp/math-fatal-contained.html"), mode: .selfContained),
            .pdf(url: URL(fileURLWithPath: "/tmp/math-fatal.pdf")),
        ] {
            do {
                _ = try await ExportService.prepare(request, target: target)
                Issue.record("Fatal output/source admission must stop every target before publication")
            } catch let ExportError.derivedContentUnavailable(diagnostics) {
                #expect(diagnostics == contribution.diagnostics)
                #expect(diagnostics.first?.sourceRange == 0 ..< 3 && diagnostics.first?.sourceOffset == 1)
            }
        }
    }

    @Test func anOrdinaryErrorStillRejectsItsHTMLAndKeepsAuthoredSource() async throws {
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "$x$", sourceGeneration: 1, theme: ExportTestSupport.lightTheme(),
                          contributions: [contribution(fatal: false)]),
            target: .html(url: URL(fileURLWithPath: "/tmp/math-nonfatal.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.bodyHTML.contains("$x$"))
        #expect(!prepared.bodyHTML.contains("DERIVED_CONTENT"))
        #expect(prepared.diagnostics.contains { $0.severity == .error && !$0.preventsPublication })
    }

    @Test func fatalPreparationLeavesAnExistingDestinationByteIdenticalAndCreatesNoSidecars() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-fatal-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("out.html")
        let original = Data("PREEXISTING_DESTINATION".utf8)
        try original.write(to: destination)
        do {
            _ = try await ExportService.exportHTML(
                ExportRequest(text: "$x$", sourceGeneration: 1, theme: ExportTestSupport.lightTheme(),
                              contributions: [contribution(fatal: true)]),
                to: .html(url: destination, mode: .standalone(style: .embedded))
            )
            Issue.record("Fatal derived content must not reach the export writer")
        } catch let ExportError.derivedContentUnavailable(diagnostics) {
            #expect(diagnostics.first?.preventsPublication == true)
        }
        #expect(try Data(contentsOf: destination) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["out.html"])
    }
}
