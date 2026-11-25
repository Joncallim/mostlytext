import DiagramWebKitPool
import Foundation
import Testing

@MainActor
@Suite("D2 vector viewport")
struct D2VectorViewportTests {
    @Test(.timeLimit(.minutes(1)))
    func generatedCanvasRefusesOversizedDimensionsBeforeSerialization() async throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resources = package.appendingPathComponent("Sources/D2Rendering/Resources", isDirectory: true)
        let bundle = try #require(Bundle(url: resources))
        let page = try await DiagramHarnessPage.make(
            harnessResourceName: "harness", bundle: bundle,
            bundledSchemeResourceNames: ["harness.html", "d2-browser.js", "render.js", "d2.wasm"]
        )
        defer { page.teardown() }

        let result = try await page.evaluate(
            """
            function svg(width, height) {
                return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}"><svg/></svg>`;
            }
            function accepted(width, height) {
                try { return opaqueD2Canvas(svg(width, height), "#FFFFFF").svg.includes("<rect"); }
                catch (_) { return false; }
            }
            function refused(width, height) {
                try { opaqueD2Canvas(svg(width, height), "#FFFFFF"); return false; }
                catch (error) { return error.message === "diagram exceeds vector viewport limit"; }
            }
            return { ok: accepted(65536, 1) && accepted(8192, 8192) &&
                         refused(65537, 1) && refused(8193, 8192) };
            """, arguments: [:]
        )
        #expect(result.succeeded, "D2 canvas accepted an oversized SVG viewport")
    }
}
