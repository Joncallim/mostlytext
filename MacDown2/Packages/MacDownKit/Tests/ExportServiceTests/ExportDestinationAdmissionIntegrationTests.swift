@testable import ExportService
import Foundation
import MarkdownEngine
import Testing

struct DestinationAdmissionIntegrationTests {
    @Test func aSuppliedAdmissionCannotBypassSourceAliasProtection() async throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let original = Data("source fixture".utf8)
        try original.write(to: item.primary)
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        let engine = DestinationAdmissionParseProbe()
        let request = ExportRequest(
            text: "# Export", sourceGeneration: 1, theme: ExportTestSupport.lightTheme(), documentURL: item.primary
        )
        await #expect(throws: ExportError.self) {
            try await ExportService.exportHTML(
                request, to: item.target, engine: engine, admission: admission
            )
        }
        #expect(await engine.calls == 0)
        #expect(try Data(contentsOf: item.primary) == original)
    }
}

private actor DestinationAdmissionParseProbe: ParseExecuting {
    var calls = 0

    func parse(_ text: String, options: MarkdownParseOptions, revision: Int) async throws -> MarkdownDocument {
        calls += 1
        return try await ParseEngine().parse(text, options: options, revision: revision)
    }
}
