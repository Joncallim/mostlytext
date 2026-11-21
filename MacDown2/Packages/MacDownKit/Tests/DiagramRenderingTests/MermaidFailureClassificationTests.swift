@testable import DiagramRendering
import Diagrams
import Testing

@Suite("Mermaid failure classification")
struct MermaidFailureClassificationTests {
    @Test func observedRasterLimitDoesNotBlameAuthoredSyntax() {
        #expect(MermaidWebRenderer.failure(for: "diagram exceeds raster pixel limit") == .rendererUnavailable)
        #expect(MermaidWebRenderer.failure(for: "Parse error on line 1") ==
            .invalidSyntax("Parse error on line 1"))
        #expect(MermaidWebRenderer.failure(for: "") == .rendererUnavailable)
        #expect(MermaidWebRenderer.failure(for: nil) == .rendererUnavailable)
        #expect(MermaidWebRenderer.failure(for: " \n") == .rendererUnavailable)
    }
}
