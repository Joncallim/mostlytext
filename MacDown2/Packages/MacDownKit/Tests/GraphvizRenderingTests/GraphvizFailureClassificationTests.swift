import DiagramsGraphviz
@testable import GraphvizRendering
import Testing

@Suite("Graphviz failure classification")
struct GraphvizFailureClassificationTests {
    @Test func observedVizAbortDoesNotBlameAuthoredDOTSyntax() {
        let observed = "Aborted(). Build with -sASSERTIONS for more info."
        #expect(GraphvizWebRenderer.failure(for: observed) == .rendererUnavailable)
        #expect(GraphvizWebRenderer.failure(for: "syntax error in line 1") ==
            .invalidSyntax("syntax error in line 1"))
        #expect(GraphvizWebRenderer.failure(for: "") == .rendererUnavailable)
        #expect(GraphvizWebRenderer.failure(for: nil) == .rendererUnavailable)
        #expect(GraphvizWebRenderer.failure(for: " \n") == .rendererUnavailable)
    }

    @Test func oversizedGeneratedCanvasDoesNotBlameAuthoredDOTSyntax() {
        #expect(GraphvizWebRenderer.failure(for: "diagram exceeds vector viewport limit") ==
            .rendererUnavailable)
    }
}
