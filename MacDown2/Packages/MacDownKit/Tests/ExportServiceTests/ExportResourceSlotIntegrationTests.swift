@testable import ExportService
import Foundation
import Testing

struct ExportResourceSlotIntegrationTests {
    @Test func ordinaryComposerRegistersOnlyGeneratedImages() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        try ExportTestSupport.writeFixture(named: "a.png", in: directory, bytes: bytes)
        let identity = ExportResourceIdentity(bytes: bytes, mimeType: "image/png")
        let path = "report.assets/" + identity.fileName
        let request = ExportRequest(
            text: "![a](a.png) ![b](a.png)\n\n`\(path)`\n\n[link](\(path))\n\n<img src=\"\(path)\">",
            sourceGeneration: 1, theme: ExportTestSupport.lightTheme(),
            documentURL: directory.appendingPathComponent("source.md")
        )
        let prepared = try await ExportService.prepare(
            request, target: .pdf(url: directory.appendingPathComponent("report.pdf"))
        )
        #expect(prepared.manifest.resources.count == 1)
        #expect(prepared.resourceSlots?.occurrences.count == 2)
        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(html.components(separatedBy: "data:image/png;base64,").count == 3)
        #expect(html.contains("<code>" + path + "</code>"))
        #expect(html.contains("href=\"" + path + "\""))
        #expect(html.contains("<img src=\"" + path + "\">"))
        #expect(!html.contains("MTRESOURCE"))
    }
}
