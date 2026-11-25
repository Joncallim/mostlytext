import DiagramWebKitPool
import Foundation
import Testing

@MainActor
@Suite("Graphviz vector viewport")
struct GraphvizVectorViewportTests {
    @Test(.timeLimit(.minutes(1)))
    func generatedCanvasRefusesOversizedDimensionsBeforeSerialization() async throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resources = package.appendingPathComponent("Sources/GraphvizRendering/Resources", isDirectory: true)
        let bundle = try #require(Bundle(url: resources))
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        defer { page.teardown() }

        let result = try await page.evaluate(
            """
            function svg(width, height) {
                return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}"></svg>`;
            }
            function accepted(width, height) {
                try {
                    return normalizedGraphvizSVG(svg(width, height), svg(width, height),
                        "#FFFFFF", "#FFFFFF", "#000000").svg.includes("<rect");
                } catch (_) { return false; }
            }
            function refused(width, height) {
                try {
                    normalizedGraphvizSVG(svg(width, height), svg(width, height),
                        "#FFFFFF", "#FFFFFF", "#000000");
                    return false;
                } catch (error) { return error.message === "diagram exceeds vector viewport limit"; }
            }
            return { ok: accepted(65536, 1) && accepted(8192, 8192) &&
                         refused(65537, 1) && refused(8193, 8192) };
            """, arguments: [:]
        )
        #expect(result.succeeded, "Graphviz canvas accepted an oversized SVG viewport")
    }
}
