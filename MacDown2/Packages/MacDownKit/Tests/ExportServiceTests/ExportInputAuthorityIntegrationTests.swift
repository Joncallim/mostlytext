@testable import ExportService
import Foundation
import Testing

struct ExportInputAuthorityIntegrationTests {
    @Test func aSavedURLAloneDoesNotGrantAccessToItsImages() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("image.png"))
        let request = ExportRequest(
            text: "![image](image.png)", sourceGeneration: 1,
            theme: ExportTestSupport.lightTheme(), documentURL: directory.appendingPathComponent("source.md")
        )
        let ordinary = try await ExportService.prepare(
            request, target: .html(
                url: directory.appendingPathComponent("out.html"),
                mode: .standalone(style: .embedded)
            )
        )
        #expect(ordinary.manifest.resources.isEmpty)
        #expect(ordinary.diagnostics.first?.severity == .warning)
        #expect(ordinary.bodyHTML.contains("image.png"))
        await #expect(throws: ExportError.self) {
            try await ExportService.prepare(
                request, target: .html(url: directory.appendingPathComponent("out.html"), mode: .selfContained)
            )
        }
    }

    @Test func anExplicitCapabilityCanBeRetainedIndependentOfMetadata() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data([1, 2, 3])
        try bytes.write(to: directory.appendingPathComponent("image.png"))
        let access = try ExportResourceAccess(openingDirectory: directory)
        let request = ExportRequest(
            text: "![image](image.png)", sourceGeneration: 1,
            theme: ExportTestSupport.lightTheme(), documentURL: nil, resourceAccess: access
        )
        let prepared = try await ExportService.prepare(
            request, target: .html(url: directory.appendingPathComponent("out.html"), mode: .selfContained)
        )
        #expect(request.resourceAccess === access)
        #expect(prepared.manifest.resources.first?.bytes == bytes)
        #expect(prepared.diagnostics.isEmpty)
    }
}
