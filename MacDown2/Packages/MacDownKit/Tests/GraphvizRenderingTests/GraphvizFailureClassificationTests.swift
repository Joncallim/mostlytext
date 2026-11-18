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
    }
}
