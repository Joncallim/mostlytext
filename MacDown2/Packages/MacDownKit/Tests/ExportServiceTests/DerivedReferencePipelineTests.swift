import ExportService
import Foundation
import Testing

struct DerivedReferencePipelineTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func productionComposerSharesReferenceIdentityForHTMLAndPDFPreparation(ending: String) async throws {
        let source = "---" + ending + "title: Doc" + ending + "---" + ending + ending +
            "[$x$][]" + ending + ending + "[$x$]: /target \"title\"" + ending
        let found = (source as NSString).range(of: "$x$", options: .literal)
        try #require(found.location != NSNotFound)
        let contribution = ExportDerivedContribution(
            sourceRange: found.location ..< NSMaxRange(found), placement: .inline,
            html: "<span class=\"math\">rendered equation</span>", sourceGeneration: 1
        )
        for target in [
            ExportTarget.html(
                url: URL(fileURLWithPath: "/tmp/reference-test.html"),
                mode: .standalone(style: .embedded)
            ),
            .pdf(url: URL(fileURLWithPath: "/tmp/reference-test.pdf")),
        ] {
            let prepared = try await ExportService.prepare(
                ExportRequest(text: source, sourceGeneration: 1, theme: ExportTestSupport.lightTheme(),
                              contributions: [contribution]), target: target
            )
            #expect(prepared.bodyHTML.contains("<a href=\"/target\" title=\"title\">"))
            #expect(prepared.bodyHTML.contains("rendered equation"))
            #expect(!prepared.bodyHTML.contains("E12INLINE"))
        }
    }

    @Test(arguments: ["javascript:alert(1)", "vbscript:msgbox(1)", "file:///private/document", "data:text/html,unsafe"])
    func repairedReferencesStillPassThroughExistingAuthoredURLPolicy(destination: String) async throws {
        let source = "[$x$][]\n\n[$x$]: " + destination
        let found = (source as NSString).range(of: "$x$", options: .literal)
        try #require(found.location != NSNotFound)
        let contribution = ExportDerivedContribution(
            sourceRange: found.location ..< NSMaxRange(found), placement: .inline,
            html: "<span class=\"math\">rendered equation</span>", sourceGeneration: 1
        )
        let prepared = try await ExportService.prepare(
            ExportRequest(text: source, sourceGeneration: 1, theme: ExportTestSupport.lightTheme(),
                          contributions: [contribution]),
            target: .html(url: URL(fileURLWithPath: "/tmp/reference-policy.html"), mode: .standalone(style: .embedded))
        )
        let scheme = String(destination.prefix { $0 != ":" }).lowercased() + ":"
        #expect(!prepared.bodyHTML.lowercased().contains("href=\"" + scheme))
        #expect(!prepared.bodyHTML.contains(destination))
        #expect(prepared.bodyHTML.contains("rendered equation"))
    }
}
